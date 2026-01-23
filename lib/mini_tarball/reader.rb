# frozen_string_literal: true

require "fileutils"

module MiniTarball
  class PathTraversalError < StandardError
    def initialize(msg = "Path traversal detected")
      super
    end
  end

  class Reader
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

      loop do
        header_data = @io.read(Header::BLOCK_SIZE)
        break if header_data.nil?

        values = HeaderParser.parse(header_data)
        break if values.nil? # End of archive or invalid

        entry = Entry.new(values)

        # Handle GNU long link for long filenames
        if values[:typeflag] == "L" # TYPE_LONG_LINK
          long_name = read_content(values[:size]).delete("\0")
          skip_padding(values[:size])

          # Read the actual entry header
          header_data = @io.read(Header::BLOCK_SIZE)
          break if header_data.nil?

          values = HeaderParser.parse(header_data)
          break if values.nil?

          values[:name] = long_name
          entry = Entry.new(values)
        end

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
