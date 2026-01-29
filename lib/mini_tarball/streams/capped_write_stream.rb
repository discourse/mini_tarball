# frozen_string_literal: true

module MiniTarball
  # Wraps an IO to enforce a maximum total write size.
  # Tracks bytes written and raises an error if the limit would be exceeded.
  #
  # @api private
  class CappedWriteStream
    # @return [Integer] total number of bytes written so far
    attr_reader :bytes_written

    # Creates a new capped write stream.
    #
    # @param io [IO] the underlying IO object
    # @param max_size [Integer] maximum total bytes allowed
    def initialize(io, max_size:)
      @io = io
      @max_size = max_size
      @bytes_written = 0
    end

    # Writes data if within the size limit.
    #
    # @param data [String] data to write
    # @return [Integer] number of bytes written
    # @raise [WriteOutOfRangeError] if write would exceed the maximum size
    def write(data)
      new_total = @bytes_written + data.bytesize
      raise WriteOutOfRangeError if new_total > @max_size

      written = @io.write(data)
      @bytes_written += written
      written
    end

    # Appends data to the stream.
    #
    # @param data [String] data to write
    # @return [self] for method chaining
    # @raise [WriteOutOfRangeError] if write would exceed the maximum size
    def <<(data)
      write(data)
      self
    end

    # Returns the number of bytes that can still be written.
    #
    # @return [Integer] remaining capacity
    def remaining
      @max_size - @bytes_written
    end
  end
end
