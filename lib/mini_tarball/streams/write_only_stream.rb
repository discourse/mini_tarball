# frozen_string_literal: true

module MiniTarball
  # Wraps an IO object to expose only write operations.
  #
  # @api private
  class WriteOnlyStream
    # @param io [IO] the underlying IO object
    def initialize(io)
      @io = io
    end

    # @param data [String] data to write
    # @return [Integer] number of bytes written
    def write(data)
      @io.write(data)
    end

    # @param data [String] data to write
    # @return [self] for method chaining
    def <<(data)
      write(data)
      self
    end
  end
end
