# frozen_string_literal: true

module MiniTarball
  # A read stream that limits reading to a specified number of bytes.
  #
  # Wraps an underlying IO and tracks bytes read, preventing reads beyond
  # the entry's declared size. This ensures each entry only reads its own data.
  #
  # @api private
  class BoundedReadStream
    # Default buffer size for reading operations.
    DEFAULT_READ_SIZE = 8192

    # @return [Integer] total number of bytes read so far
    attr_reader :bytes_read

    # Creates a new bounded read stream.
    #
    # @param io [IO] the underlying IO object
    # @param size [Integer] maximum bytes allowed to read
    def initialize(io, size)
      @io = io
      @size = size
      @bytes_read = 0
    end

    # Reads up to the specified number of bytes.
    #
    # @param length [Integer, nil] maximum bytes to read (defaults to remaining)
    # @param buffer [String, nil] optional buffer to read into
    # @return [String, nil] the data read, or nil at end of entry
    # @raise [TruncatedArchiveError] if underlying IO returns less data than expected
    def read(length = nil, buffer = nil)
      return nil if @bytes_read >= @size
      return(buffer ? buffer.replace("") : "") if length == 0

      # Calculate how many bytes we can actually read
      max_read = @size - @bytes_read
      read_length = length ? [length, max_read].min : max_read

      data = @io.read(read_length, buffer)

      if data.nil? || data.bytesize < read_length
        raise TruncatedArchiveError, "Unexpected end of archive at byte #{@bytes_read}"
      end

      @bytes_read += data.bytesize
      data
    end

    # Reads a single line from the stream.
    #
    # @param separator [String] the line separator (default: newline)
    # @param limit [Integer, nil] maximum bytes to read
    # @return [String, nil] the line, or nil at end of entry
    def gets(separator = $/, limit = nil)
      return nil if @bytes_read >= @size

      line = +""
      max_to_read = @size - @bytes_read
      limit = max_to_read if limit.nil? || limit > max_to_read

      while line.bytesize < limit
        char = read(1)
        break if char.nil?

        line << char
        break if separator && line.end_with?(separator)
      end

      line.empty? ? nil : line
    end

    # Iterates over each byte in the stream.
    #
    # @yieldparam byte [Integer] each byte value
    # @return [self, Enumerator] self if block given, otherwise Enumerator
    def each_byte(&block)
      return enum_for(:each_byte) unless block_given?

      while (data = read(DEFAULT_READ_SIZE))
        data.each_byte(&block)
      end
      self
    end

    # Returns the number of bytes remaining to be read.
    #
    # @return [Integer]
    def remaining
      @size - @bytes_read
    end

    # Returns whether we've read all available bytes.
    #
    # @return [Boolean]
    def eof?
      @bytes_read >= @size
    end

    # Skips past remaining bytes in this entry.
    # Used when the caller doesn't want to read the content.
    #
    # @return [void]
    def skip
      remaining_bytes = remaining
      return if remaining_bytes == 0

      if @io.respond_to?(:seek) && @io.respond_to?(:size) && @io.respond_to?(:pos)
        available = @io.size - @io.pos
        if available < remaining_bytes
          raise TruncatedArchiveError, "Unexpected end of archive at byte #{@bytes_read}"
        end
        @io.seek(remaining_bytes, IO::SEEK_CUR)
        @bytes_read = @size
        return
      end

      # For non-seekable IO (or seekable IO without size), read and discard
      while remaining.positive?
        to_read = [DEFAULT_READ_SIZE, remaining].min
        data = @io.read(to_read)
        if data.nil? || data.bytesize < to_read
          raise TruncatedArchiveError, "Unexpected end of archive at byte #{@bytes_read}"
        end
        @bytes_read += data.bytesize
      end
    end

    # Copies the stream contents to another IO.
    #
    # @param dest [IO] destination IO
    # @return [Integer] number of bytes copied
    def copy_to(dest)
      copied = 0
      while (data = read(DEFAULT_READ_SIZE))
        dest.write(data)
        copied += data.bytesize
      end
      copied
    end
  end
end
