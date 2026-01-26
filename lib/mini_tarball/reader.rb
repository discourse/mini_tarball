# frozen_string_literal: true

require "fileutils"

module MiniTarball
  class PathTraversalError < StandardError
    def initialize(msg = "Path traversal detected")
      super
    end
  end

  class Reader
    # Maximum size for long name/linkname entries (64KB)
    MAX_LONG_NAME_SIZE = 65_535
    private_constant :MAX_LONG_NAME_SIZE

    def self.use(io)
      reader = new(io)
      yield reader
    ensure
      reader&.close
    end

    def initialize(io)
      @io = io
      @closed = false
    end

    def each_entry
      return enum_for(:each_entry) unless block_given?

      ensure_not_closed

      long_linkname = nil
      long_name = nil

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
      @io.read(bytes) if bytes > 0
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

      full_path
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
