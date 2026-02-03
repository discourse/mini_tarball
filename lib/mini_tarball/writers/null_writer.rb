# frozen_string_literal: true

module MiniTarball
  # Utility for writing null bytes in chunks to avoid large allocations.
  #
  # @api private
  module NullWriter
    CHUNK_SIZE = 65_536
    CHUNK = ("\0" * CHUNK_SIZE).freeze
    private_constant :CHUNK_SIZE, :CHUNK

    # Writes null bytes to an IO stream in chunks.
    #
    # @param io [IO] the IO stream to write to
    # @param count [Integer] number of null bytes to write
    # @return [void]
    def self.write(io, count)
      return if count <= 0

      remaining = count
      while remaining > 0
        to_write = [remaining, CHUNK_SIZE].min
        io.write(to_write == CHUNK_SIZE ? CHUNK : CHUNK.byteslice(0, to_write))
        remaining -= to_write
      end
    end
  end
end
