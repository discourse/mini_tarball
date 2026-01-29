# frozen_string_literal: true

module MiniTarball
  # Wraps an IO to restrict writes to a specific byte range.
  # Raises an error if writes would fall outside the defined region.
  #
  # @api private
  class LimitedSizeStream
    # @return [Integer] the starting byte position of the writable region
    attr_reader :start_position

    # @return [Integer] the ending byte position (exclusive) of the writable region
    attr_reader :end_position

    private attr_reader :io

    # Creates a new limited size stream.
    #
    # @param io [IO] the underlying IO object
    # @param start_position [Integer] the starting byte position
    # @param size [Integer] the maximum number of bytes that can be written
    def initialize(io, start_position:, size:)
      @io = io
      @start_position = start_position
      @end_position = start_position + size
    end

    # Writes data within the allowed region.
    #
    # @param data [String] data to write
    # @return [Integer] number of bytes written
    # @raise [WriteOutOfRangeError] if write would exceed the allowed region
    def write(data)
      current_position = io.pos

      if current_position < start_position || current_position + data.bytesize > end_position
        raise WriteOutOfRangeError
      end

      io.write(data)
    end

    # Appends data to the stream.
    #
    # @param data [String] data to write
    # @return [self] for method chaining
    # @raise [WriteOutOfRangeError] if write would exceed the allowed region
    def <<(data)
      write(data)
      self
    end
  end
end
