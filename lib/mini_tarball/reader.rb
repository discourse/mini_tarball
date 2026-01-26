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

  class TruncatedArchiveError < StandardError
    def initialize(msg = "Archive is truncated")
      super
    end
  end

  class Reader
    # Maximum size for long name/linkname entries (64KB)
    MAX_LONG_NAME_SIZE = 65_535

    # Maximum number of internal headers (long name/linkname) to prevent DoS
    MAX_INTERNAL_HEADERS = 200_000

    # Chunk size for skipping content (64KB)
    SKIP_CHUNK_SIZE = 65_536

    # Default maximum file size (8GB)
    DEFAULT_MAX_FILE_SIZE = 8_589_934_592

    # Default maximum total size (50GB)
    DEFAULT_MAX_TOTAL_SIZE = 53_687_091_200

    # Default maximum entry count (100,000)
    DEFAULT_MAX_ENTRY_COUNT = 100_000

    private_constant :MAX_LONG_NAME_SIZE,
                     :MAX_INTERNAL_HEADERS,
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
      internal_header_count = 0

      loop do
        header_data = @io.read(Header::BLOCK_SIZE)
        break if header_data.nil?

        values = HeaderParser.parse(header_data)
        break if values.nil? # End of archive or invalid

        # Handle GNU long linkname (typeflag K) for long symlink/hardlink targets
        if values[:typeflag] == "K"
          raise InvalidHeaderError, "Long linkname too large" if values[:size] > MAX_LONG_NAME_SIZE
          internal_header_count += 1
          if internal_header_count > MAX_INTERNAL_HEADERS
            raise ArchiveLimitError, "Too many internal headers"
          end
          total_size += values[:size]
          if total_size > @max_total_size
            raise ArchiveLimitError, "Total size exceeds maximum (#{@max_total_size} bytes)"
          end
          long_linkname = read_content(values[:size]).delete("\0")
          skip_padding(values[:size])
          next
        end

        # Handle GNU long link (typeflag L) for long filenames
        if values[:typeflag] == "L"
          raise InvalidHeaderError, "Long name too large" if values[:size] > MAX_LONG_NAME_SIZE
          internal_header_count += 1
          if internal_header_count > MAX_INTERNAL_HEADERS
            raise ArchiveLimitError, "Too many internal headers"
          end
          total_size += values[:size]
          if total_size > @max_total_size
            raise ArchiveLimitError, "Total size exceeds maximum (#{@max_total_size} bytes)"
          end
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

    # Iterates over regular file entries only, skipping directories and links.
    # Convenient for streaming file contents without filesystem extraction.
    #
    # @example Streaming files to S3
    #   Reader.use(tar_io) do |reader|
    #     reader.each_file do |entry, stream|
    #       s3.put_object(bucket: "bucket", key: entry.name, body: stream)
    #     end
    #   end
    #
    # @yield [entry, stream] Yields each file entry and its content stream
    # @yieldparam entry [Entry] The file entry metadata
    # @yieldparam stream [BoundedReadStream] The file content stream
    # @return [Enumerator, self] Returns Enumerator if no block given, self otherwise
    def each_file
      return enum_for(:each_file) unless block_given?

      each_entry { |entry, stream| yield entry, stream if entry.file? }

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
      data = @io.read(size)
      raise TruncatedArchiveError, "Unexpected end of archive" if data.nil? || data.bytesize < size
      data
    end

    def skip_remaining(bytes)
      while bytes > 0
        chunk = [bytes, SKIP_CHUNK_SIZE].min
        data = @io.read(chunk)
        raise TruncatedArchiveError, "Unexpected end of archive" if data.nil?
        bytes -= data.bytesize
      end
    end

    def skip_padding(content_size)
      padding = (Header::BLOCK_SIZE - (content_size % Header::BLOCK_SIZE)) % Header::BLOCK_SIZE
      return if padding == 0

      data = @io.read(padding)
      raise TruncatedArchiveError, "Unexpected end of archive" if data.nil? || data.bytesize < padding
    end

    def extract_entry(entry, stream, destination)
      target_path = safe_path(entry.name, destination)

      if entry.directory?
        ensure_not_symlink_target(target_path)
        FileUtils.mkdir_p(target_path)
      elsif entry.symlink?
        validate_symlink_target(entry.linkname, destination, target_path)
        FileUtils.mkdir_p(File.dirname(target_path))
        File.symlink(entry.linkname, target_path)
      elsif entry.hardlink?
        link_target = safe_path(entry.linkname, destination)
        ensure_not_symlink_target(target_path)
        ensure_not_symlink_target(link_target)
        FileUtils.mkdir_p(File.dirname(target_path))
        File.link(link_target, target_path)
      elsif entry.file?
        ensure_not_symlink_target(target_path)
        FileUtils.mkdir_p(File.dirname(target_path))
        File.open(target_path, "wb") { |f| IO.copy_stream(stream, f) }
        File.chmod(entry.mode, target_path) if entry.mode
      end
    end

    def safe_path(name, destination)
      # Remove leading slashes and resolve the path
      clean_name = name.sub(%r{^/+}, "")
      full_path = normalize_path(File.expand_path(File.join(destination, clean_name)))
      normalized_dest = normalize_path(destination)

      # Ensure the resolved path is within destination
      raise PathTraversalError unless path_within?(full_path, normalized_dest)

      # Verify no symlinks in existing path components could escape
      validate_path_components(full_path, normalized_dest)

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
        resolved = normalize_path(File.realpath(path))
        unless path_within?(resolved, destination)
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
        resolved = normalize_path(File.expand_path(target, File.dirname(link_path)))
        raise PathTraversalError unless path_within?(resolved, destination)
      end
    end

    def ensure_not_symlink_target(path)
      return unless File.symlink?(path)

      raise PathTraversalError, "Symlink at destination path"
    end

    # Normalize path separators to forward slashes for consistent comparison
    def normalize_path(path)
      path.tr("\\", "/")
    end

    # Check if path is within or equal to destination
    def path_within?(path, destination)
      path == destination || path.start_with?(destination + "/")
    end
  end
end
