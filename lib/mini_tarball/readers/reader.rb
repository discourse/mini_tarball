# frozen_string_literal: true

require "fileutils"

module MiniTarball
  # Reads tar archives with streaming support.
  #
  # Reader supports GNU tar, POSIX ustar, and pax formats. It handles long
  # filenames via GNU extensions and pax extended headers automatically.
  #
  # Recognized typeflags:
  # - Regular files ("0" or "\0")
  # - Directories ("5")
  # - Symlinks ("2")
  # - Hardlinks ("1")
  # - GNU long name ("L"), GNU long linkname ("K")
  # - Pax extended ("x"), pax global ("g")
  #
  # Metadata entries (GNU/pax) are consumed internally and are not yielded.
  # When both GNU long names and pax path/linkpath are present, pax attributes
  # take precedence. Unknown types are treated as regular file payloads during extraction.
  #
  # @example Block-based reading (recommended)
  #   Reader.open("archive.tar") do |reader|
  #     reader.each_entry do |entry, stream|
  #       puts "#{entry.name}: #{stream.read}" if entry.file?
  #     end
  #   end
  #
  # @example Using with IO
  #   Reader.use(io) do |reader|
  #     reader.each_entry { |entry, stream| ... if entry.file? }
  #   end
  #
  # @example Enumerator support
  #   reader.each_entry.map { |entry, _| entry.name }
  class Reader
    # Default limits to prevent resource exhaustion
    DEFAULT_MAX_FILE_SIZE = 8_589_934_592 # 8GB per file
    DEFAULT_MAX_TOTAL_SIZE = 53_687_091_200 # 50GB total
    DEFAULT_MAX_ENTRY_COUNT = 100_000 # 100K entries

    # Metadata entries (GNU long names, pax headers) are read fully into
    # memory, so they get a much smaller cap than regular file entries.
    MAX_METADATA_SIZE = 1_048_576 # 1MB

    METADATA_TYPEFLAGS = [
      Header::TYPE[:gnu_long_name],
      Header::TYPE[:gnu_long_linkname],
      Header::TYPE[:pax_global],
      Header::TYPE[:pax_extended],
    ].freeze
    private_constant :METADATA_TYPEFLAGS

    # Opens a tar file and yields a reader.
    # The file is automatically closed when the block returns.
    #
    # @param filename [String] path to the tar file
    # @param limits [Hash] optional limits (max_file_size, max_total_size, max_entry_count)
    # @yieldparam reader [Reader] the reader instance
    # @return [void]
    def self.open(filename, **limits)
      File.open(filename, "rb") { |file| use(file, **limits) { |reader| yield(reader) } }
    end

    # Wraps an IO object and yields a reader.
    # The reader is automatically closed when the block returns.
    #
    # @param io [IO] an IO-like object supporting +read+
    # @param limits [Hash] optional limits
    # @yieldparam reader [Reader] the reader instance
    # @return [void]
    def self.use(io, **limits)
      reader = new(io, **limits)
      begin
        yield(reader)
      ensure
        reader.close
      end
      nil
    end

    # Creates a new reader.
    #
    # @param io [IO] an IO-like object supporting +read+
    # @param max_file_size [Integer, nil] maximum size per file (nil disables)
    # @param max_total_size [Integer, nil] maximum total extracted size (nil disables)
    # @param max_entry_count [Integer, nil] maximum number of entries (nil disables)
    def initialize(
      io,
      max_file_size: DEFAULT_MAX_FILE_SIZE,
      max_total_size: DEFAULT_MAX_TOTAL_SIZE,
      max_entry_count: DEFAULT_MAX_ENTRY_COUNT
    )
      @io = io
      @max_file_size = max_file_size
      @max_total_size = max_total_size
      @max_entry_count = max_entry_count
      @closed = false
      @total_size_read = 0
      @entry_count = 0
      @pax_global_attributes = {}
      @finished = false
    end

    # Iterates over all entries in the archive, excluding metadata entries.
    #
    # @yieldparam entry [Entry] the entry metadata
    # @yieldparam stream [BoundedReadStream] stream to read entry content
    # @return [self, Enumerator] self if block given, otherwise Enumerator
    def each_entry(&block)
      return enum_for(:each_entry) unless block_given?

      ensure_not_closed!

      pending_long_name = nil
      pending_long_linkname = nil
      pending_pax_attributes = nil

      while (header = read_header)
        if METADATA_TYPEFLAGS.include?(header.typeflag)
          data = read_metadata_entry(header)

          case header.typeflag
          when Header::TYPE[:gnu_long_name]
            pending_long_name = parse_gnu_long_name(data)
          when Header::TYPE[:gnu_long_linkname]
            pending_long_linkname = parse_gnu_long_name(data)
          when Header::TYPE[:pax_global]
            @pax_global_attributes = PaxParser.parse(data)
          when Header::TYPE[:pax_extended]
            pending_pax_attributes = PaxParser.parse(data)
          end

          next
        end

        pax_attributes = merged_pax_attributes(pending_pax_attributes)
        entry = Entry.from_header(header, pax_attributes:)

        # Apply pending GNU long names if present (pax overrides take precedence).
        entry =
          apply_gnu_long_names(
            entry,
            long_name: pending_long_name,
            long_linkname: pending_long_linkname,
            pax_attributes:,
          )
        pending_long_name = nil
        pending_long_linkname = nil
        pending_pax_attributes = nil

        content_size = entry.size
        stream = create_content_stream(content_size)

        check_limits!(entry)
        block.call(entry, stream)

        finalize_entry(stream, content_size)
      end

      self
    end

    # Extracts all entries to a destination directory.
    #
    # Creates directories, writes files, and creates symlinks as needed.
    # All paths are validated to prevent extraction outside the destination.
    #
    # @param destination [String] the directory to extract to (must exist)
    # @param preserve_permissions [Boolean] whether to set file modes (default: true)
    # @param preserve_mtime [Boolean] whether to set modification times (default: true)
    # @param before [Proc, nil] hook called before extraction (entry, path). Return false to skip.
    # @param after [Proc, nil] hook called after extraction (entry, path)
    # @return [Array<String>] list of extracted paths
    # @raise [PathTraversalError] if any entry would extract outside destination
    # @raise [Errno::ENOENT] if destination doesn't exist
    def extract_all(
      destination,
      preserve_permissions: true,
      preserve_mtime: true,
      before: nil,
      after: nil
    )
      ensure_not_closed!

      # Ensure destination exists and is a directory
      unless File.directory?(destination)
        raise Errno::ENOENT, "Destination does not exist: #{destination}"
      end

      extracted = []

      each_entry do |entry, stream|
        ExtractionValidator.validate_name_components!(entry.name)
        path =
          ExtractionValidator.validate_extraction_path!(
            entry.name,
            destination,
            allow_final_symlink: entry.symlink?,
          )

        next if before && before.call(entry, path) == false

        extract_entry(entry:, stream:, path:, destination:, preserve_permissions:, preserve_mtime:)
        extracted << path
        after&.call(entry, path)
      end

      extracted
    end

    # Returns whether the reader has been closed.
    # @return [Boolean]
    def closed?
      @closed
    end

    # Closes the reader.
    # Calling close on an already-closed reader is a no-op.
    #
    # @return [void]
    def close
      return if closed?
      @io.close if @io.respond_to?(:close)
    ensure
      @closed = true
    end

    private

    def read_header
      return nil if @finished

      data = read_exact!(Header::BLOCK_SIZE, "header")

      # Check for end-of-archive (two consecutive null blocks)
      if HeaderParser.null_block?(data)
        second = read_exact!(Header::BLOCK_SIZE, "end-of-archive marker")
        unless HeaderParser.null_block?(second)
          raise InvalidHeaderError, "Invalid end-of-archive marker"
        end
        @finished = true
        return nil
      end

      HeaderParser.parse(data)
    end

    def create_content_stream(size)
      BoundedReadStream.new(@io, size)
    end

    # Reads a metadata entry (GNU long name, pax header) fully into memory.
    # These entries are bounded by MAX_METADATA_SIZE instead of max_file_size.
    def read_metadata_entry(header)
      entry = Entry.from_header(header)
      check_limits!(entry)

      if header.size > MAX_METADATA_SIZE
        raise ArchiveLimitError,
              "Metadata entry too large: #{header.size} bytes (max: #{MAX_METADATA_SIZE})"
      end

      stream = create_content_stream(header.size)
      data = stream.read || ""
      finalize_entry(stream, header.size)
      data
    end

    def parse_gnu_long_name(data)
      raise InvalidHeaderError, "Empty GNU long name" if data.empty?

      # GNU long name is null-terminated
      data.chomp!("\0")
      data
    end

    def merged_pax_attributes(entry_attributes)
      return nil if @pax_global_attributes.empty? && entry_attributes.nil?
      @pax_global_attributes.merge(entry_attributes || {})
    end

    def apply_gnu_long_names(entry, long_name:, long_linkname:, pax_attributes:)
      return entry unless long_name || long_linkname

      if pax_attributes
        long_name = nil if pax_attributes.key?("path")
        long_linkname = nil if pax_attributes.key?("linkpath")
      end

      return entry unless long_name || long_linkname

      Entry.new(
        name: long_name || entry.name,
        mode: entry.mode,
        uid: entry.uid,
        gid: entry.gid,
        size: entry.size,
        mtime: entry.mtime,
        typeflag: entry.typeflag,
        linkname: long_linkname || entry.linkname,
        uname: entry.uname,
        gname: entry.gname,
        devmajor: entry.devmajor,
        devminor: entry.devminor,
      )
    end

    def skip_to_next_block(content_size)
      # Skip any remaining padding to reach the next block boundary
      padding = Header.padding_for(content_size)
      skip_bytes!(padding, "padding") if padding > 0
    end

    def finalize_entry(stream, content_size)
      # Ensure all content is consumed
      stream.skip unless stream.eof?

      # Update total size tracking
      @total_size_read += content_size

      # Skip padding to next block boundary
      skip_to_next_block(content_size)
    end

    def check_limits!(entry)
      @entry_count += 1

      if @max_entry_count && @entry_count > @max_entry_count
        raise ArchiveLimitError, "Entry count limit exceeded (max: #{@max_entry_count})"
      end

      if @max_file_size && entry.size > @max_file_size
        raise ArchiveLimitError,
              "Entry size limit exceeded: #{entry.name} is #{entry.size} bytes (max: #{@max_file_size})"
      end

      if @max_total_size && (@total_size_read + entry.size) > @max_total_size
        raise ArchiveLimitError, "Total size limit exceeded (max: #{@max_total_size})"
      end
    end

    def ensure_not_closed!
      raise IOError, "Reader is closed" if closed?
    end

    def extract_entry(entry:, stream:, path:, destination:, preserve_permissions:, preserve_mtime:)
      case
      when entry.directory?
        extract_directory(path, entry, preserve_permissions:, preserve_mtime:)
      when entry.file?
        extract_file(path:, entry:, stream:, preserve_permissions:, preserve_mtime:)
      when entry.symlink?
        extract_symlink(path:, entry:, destination:)
      when entry.hardlink?
        extract_hardlink(path:, entry:, destination:)
      else
        # Unknown types are extracted as regular files (GNU tar behavior)
        extract_file(path:, entry:, stream:, preserve_permissions:, preserve_mtime:)
      end
    end

    def extract_directory(path, entry, preserve_permissions:, preserve_mtime:)
      FileUtils.mkdir_p(path)
      apply_permissions(path, entry) if preserve_permissions
      apply_mtime(path, entry) if preserve_mtime
    end

    def extract_file(path:, entry:, stream:, preserve_permissions:, preserve_mtime:)
      # Ensure parent directory exists
      FileUtils.mkdir_p(File.dirname(path))

      # Write file content
      File.open(path, "wb") { |f| stream.copy_to(f) }

      apply_permissions(path, entry) if preserve_permissions
      apply_mtime(path, entry) if preserve_mtime
    end

    def extract_symlink(path:, entry:, destination:)
      # Validate symlink target
      ExtractionValidator.validate_symlink_target!(
        link_path: path,
        target: entry.linkname,
        destination:,
      )

      # Ensure parent directory exists
      FileUtils.mkdir_p(File.dirname(path))

      # Remove existing file if present (symlink creation fails otherwise)
      File.unlink(path) if File.symlink?(path) || File.exist?(path)

      File.symlink(entry.linkname, path)
    end

    def extract_hardlink(path:, entry:, destination:)
      # Validate target path
      target_path = ExtractionValidator.validate_extraction_path!(entry.linkname, destination)

      # Skip if hardlink points to itself (can happen with duplicate entries)
      return if path == target_path

      # Ensure parent directory exists
      FileUtils.mkdir_p(File.dirname(path))

      # Remove existing file if present
      File.unlink(path) if File.exist?(path)

      File.link(target_path, path)
    end

    def apply_permissions(path, entry)
      # Only apply the permission bits, not the file type bits
      File.chmod(entry.mode & 0o7777, path)
    rescue Errno::EPERM, Errno::ENOTSUP
      # Ignore permission errors (e.g., on some filesystems or without root)
    end

    def apply_mtime(path, entry)
      File.utime(entry.mtime, entry.mtime, path) if entry.mtime
    rescue Errno::EPERM, Errno::ENOTSUP
      # Ignore timestamp errors
    end

    def read_exact!(length, context)
      data = @io.read(length)
      if data.nil? || data.bytesize < length
        raise TruncatedArchiveError, "Unexpected end of archive while reading #{context}"
      end
      data
    end

    def skip_bytes!(length, context)
      return if length == 0

      BoundedReadStream.new(@io, length).skip
    rescue TruncatedArchiveError
      raise TruncatedArchiveError, "Unexpected end of archive while reading #{context}"
    end
  end
end
