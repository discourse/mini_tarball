# frozen_string_literal: true

module MiniTarball
  # Wraps an IO to enforce a maximum total write size.
  # Tracks bytes written and raises an error if the limit would be exceeded.
  #
  # @api private
  class CappedWriteStream
    # @return [Integer] total number of bytes written so far
    attr_reader :bytes_written

    # @param io [IO] the underlying IO object
    # @param max_size [Integer] maximum total bytes allowed
    def initialize(io, max_size:)
      @io = io
      @max_size = max_size
      @bytes_written = 0
    end

    # Writes data if within the size limit.
    #
    # @param data [#to_s] data to write, converted like IO#write does
    # @return [Integer] number of bytes written
    # @raise [WriteOutOfRangeError] if write would exceed the maximum size
    def write(data)
      data = data.to_s
      size = data.bytesize
      if @bytes_written + size > @max_size
        raise WriteOutOfRangeError,
              "Write of #{size} bytes exceeds limit (#{@bytes_written}/#{@max_size} bytes used)"
      end

      @io.write(data)
      @bytes_written += size
      size
    end

    # @param data [String] data to write
    # @return [self] for method chaining
    # @raise [WriteOutOfRangeError] if write would exceed the maximum size
    def <<(data)
      write(data)
      self
    end

    # @return [Integer] remaining capacity
    def remaining
      @max_size - @bytes_written
    end
  end
end
