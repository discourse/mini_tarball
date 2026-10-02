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
      @buffer = "".b
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

      data = @buffer.empty? ? read_from_io(read_length, buffer) : read_buffered(read_length, buffer)
      @bytes_read += data.bytesize
      data
    end

    # Reads a single line from the stream.
    #
    # Follows the IO#gets contract: a sole Integer argument is treated as the
    # limit, with the default separator.
    #
    # @param separator [String, Integer] the line separator (default: newline),
    #   or the limit when it is the only argument
    # @param limit [Integer, nil] maximum bytes to read
    # @return [String, nil] the line, or nil at end of entry
    def gets(separator = $/, limit = nil)
      if separator.is_a?(Integer) && limit.nil?
        limit = separator
        separator = $/
      end

      return nil if @bytes_read >= @size

      max_to_read = @size - @bytes_read
      limit = max_to_read if limit.nil? || limit > max_to_read

      line = read(line_length(separator, limit))
      line.nil? || line.empty? ? nil : line
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
      # Bytes buffered by #gets were already consumed from the underlying IO
      @bytes_read += @buffer.bytesize
      @buffer.clear

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

    private

    def read_from_io(length, buffer)
      data = @io.read(length, buffer)

      if data.nil? || data.bytesize < length
        raise TruncatedArchiveError, "Unexpected end of archive at byte #{@bytes_read}"
      end

      data
    end

    # Serves a read from the internal buffer filled by #gets, falling back to
    # the underlying IO for any missing bytes.
    def read_buffered(length, buffer)
      data = @buffer.byteslice(0, length)
      @buffer = @buffer.byteslice(data.bytesize..) || "".b

      missing = length - data.bytesize
      data << read_from_io(missing, nil).force_encoding(Encoding::BINARY) if missing > 0

      buffer ? buffer.replace(data) : data
    end

    # Fills the internal buffer until it contains the separator, at least
    # +limit+ bytes, or the entry is exhausted, then returns the line length.
    def line_length(separator, limit)
      search_from = 0

      loop do
        if separator
          index = @buffer.index(separator, search_from)
          return [index + separator.bytesize, limit].min if index

          # The separator can straddle a chunk boundary
          search_from = [@buffer.bytesize - separator.bytesize + 1, 0].max
        end

        break if @buffer.bytesize >= limit || !fill_buffer
      end

      [limit, @buffer.bytesize].min
    end

    # Reads the next chunk from the underlying IO into the internal buffer.
    # Returns false once the whole entry has been buffered.
    def fill_buffer
      buffered_end = @bytes_read + @buffer.bytesize
      to_read = [DEFAULT_READ_SIZE, @size - buffered_end].min
      return false if to_read <= 0

      chunk = @io.read(to_read)
      if chunk.nil? || chunk.bytesize < to_read
        raise TruncatedArchiveError, "Unexpected end of archive at byte #{buffered_end}"
      end

      @buffer << chunk.force_encoding(Encoding::BINARY)
      true
    end
  end
end
