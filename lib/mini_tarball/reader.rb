# frozen_string_literal: true

require "fileutils"

module MiniTarball
  class PathTraversalError < StandardError
    def initialize(msg = "Path traversal detected")
      super
    end
  end

  class ArchiveLimitError < StandardError
    def initialize(msg = "Archive limit exceeded")
      super
    end
  end

  class Reader
    # Maximum size for long name/linkname entries (64KB)
    MAX_LONG_NAME_SIZE = 65_535

    # Chunk size for skipping content (64KB)
    SKIP_CHUNK_SIZE = 65_536

    # Default maximum file size (8GB)
    DEFAULT_MAX_FILE_SIZE = 8_589_934_592

    # Default maximum total size (50GB)
    DEFAULT_MAX_TOTAL_SIZE = 53_687_091_200

    # Default maximum entry count (100,000)
    DEFAULT_MAX_ENTRY_COUNT = 100_000

    private_constant :MAX_LONG_NAME_SIZE,
                     :SKIP_CHUNK_SIZE,
                     :DEFAULT_MAX_FILE_SIZE,
                     :DEFAULT_MAX_TOTAL_SIZE,
                     :DEFAULT_MAX_ENTRY_COUNT

    def self.use(
      io,
      max_file_size: DEFAULT_MAX_FILE_SIZE,
      max_total_size: DEFAULT_MAX_TOTAL_SIZE,
      max_entry_count: DEFAULT_MAX_ENTRY_COUNT
    )
      reader = new(io, max_file_size:, max_total_size:, max_entry_count:)
      yield reader
    ensure
      reader&.close
    end

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
    end

    def each_entry
      return enum_for(:each_entry) unless block_given?

      ensure_not_closed

      long_linkname = nil
      long_name = nil
      total_size = 0
      entry_count = 0

      loop do
        header_data = @io.read(Header::BLOCK_SIZE)
        break if header_data.nil?

        values = HeaderParser.parse(header_data)
        break if values.nil? # End of archive or invalid

        # Handle GNU long linkname (typeflag K) for long symlink/hardlink targets
        if values[:typeflag] == "K"
          raise InvalidHeaderError, "Long linkname too large" if values[:size] > MAX_LONG_NAME_SIZE
          long_linkname = read_content(values[:size]).delete("\0")
          skip_padding(values[:size])
          next
        end

        # Handle GNU long link (typeflag L) for long filenames
        if values[:typeflag] == "L"
          raise InvalidHeaderError, "Long name too large" if values[:size] > MAX_LONG_NAME_SIZE
          long_name = read_content(values[:size]).delete("\0")
          skip_padding(values[:size])
          next
        end

        # Apply any pending long name/linkname
        values[:name] = long_name if long_name
        values[:linkname] = long_linkname if long_linkname
        long_name = nil
        long_linkname = nil

        # Validate file size
        if values[:size] && values[:size] > @max_file_size
          raise InvalidHeaderError, "File size exceeds maximum (#{@max_file_size} bytes)"
        end

        # Validate entry count
        entry_count += 1
        if entry_count > @max_entry_count
          raise ArchiveLimitError, "Entry count exceeds maximum (#{@max_entry_count})"
        end

        # Validate total size
        total_size += values[:size] || 0
        if total_size > @max_total_size
          raise ArchiveLimitError, "Total size exceeds maximum (#{@max_total_size} bytes)"
        end

        entry = Entry.new(values)
        content_stream = BoundedReadStream.new(@io, size: entry.size)
        yield entry, content_stream

        # Skip any unread content and padding
        skip_remaining(content_stream.remaining)
        skip_padding(entry.size)
      end

      self
    end

    def extract_all(destination)
      destination = File.expand_path(destination)
      FileUtils.mkdir_p(destination)

      each_entry { |entry, stream| extract_entry(entry, stream, destination) }

      self
    end

    def close
      ensure_not_closed
      @closed = true
    end

    private

    def ensure_not_closed
      raise "Reader is already closed" if @closed
    end

    def read_content(size)
      @io.read(size)
    end

    def skip_remaining(bytes)
      while bytes > 0
        chunk = [bytes, SKIP_CHUNK_SIZE].min
        @io.read(chunk)
        bytes -= chunk
      end
    end

    def skip_padding(content_size)
      padding = (Header::BLOCK_SIZE - (content_size % Header::BLOCK_SIZE)) % Header::BLOCK_SIZE
      @io.read(padding) if padding > 0
    end

    def extract_entry(entry, stream, destination)
      target_path = safe_path(entry.name, destination)

      if entry.directory?
        FileUtils.mkdir_p(target_path)
      elsif entry.symlink?
        validate_symlink_target(entry.linkname, destination, target_path)
        FileUtils.mkdir_p(File.dirname(target_path))
        File.symlink(entry.linkname, target_path)
      elsif entry.hardlink?
        link_target = safe_path(entry.linkname, destination)
        FileUtils.mkdir_p(File.dirname(target_path))
        File.link(link_target, target_path)
      elsif entry.file?
        FileUtils.mkdir_p(File.dirname(target_path))
        File.open(target_path, "wb") { |f| IO.copy_stream(stream, f) }
        File.chmod(entry.mode, target_path) if entry.mode
      end
    end

    def safe_path(name, destination)
      # Remove leading slashes and resolve the path
      clean_name = name.sub(%r{^/+}, "")
      full_path = File.expand_path(File.join(destination, clean_name))

      # Ensure the resolved path is within destination
      unless full_path.start_with?(destination + "/") || full_path == destination
        raise PathTraversalError
      end

      # Verify no symlinks in existing path components could escape
      validate_path_components(full_path, destination)

      full_path
    end

    def validate_path_components(full_path, destination)
      # Check each existing directory component for symlinks escaping destination
      path = destination
      relative = full_path.delete_prefix(destination + "/")

      # Check all components except the last (which is the file/dir being created)
      relative.split("/")[0..-2].each do |component|
        path = File.join(path, component)
        next unless File.symlink?(path)

        # Resolve symlink and verify it stays within destination
        resolved = File.realpath(path)
        unless resolved.start_with?(destination + "/") || resolved == destination
          raise PathTraversalError, "Symlink in path escapes destination"
        end
      end
    end

    def validate_symlink_target(target, destination, link_path)
      return if target.nil? || target.empty?

      # Resolve where the symlink would point
      if target.start_with?("/")
        # Absolute symlink - not allowed
        raise PathTraversalError
      else
        # Relative symlink - check where it resolves
        resolved = File.expand_path(target, File.dirname(link_path))
        unless resolved.start_with?(destination + "/") || resolved == destination
          raise PathTraversalError
        end
      end
    end
  end
end
