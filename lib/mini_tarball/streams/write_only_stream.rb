# frozen_string_literal: true

module MiniTarball
  # Wraps an IO object to expose only write operations.
  # Provides a minimal write-only interface for tar entry content.
  #
  # @api private
  class WriteOnlyStream
    # Creates a new write-only stream.
    #
    # @param io [IO] the underlying IO object
    def initialize(io)
      @io = io
    end

    # Writes data to the underlying stream.
    #
    # @param args [Array] arguments forwarded to IO#write
    # @return [Integer] number of bytes written
    def write(...)
      @io.write(...)
    end

    # Appends data to the stream.
    #
    # @param data [String] data to write
    # @return [self] for method chaining
    def <<(data)
      write(data)
      self
    end
  end
end
