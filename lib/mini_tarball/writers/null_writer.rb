# frozen_string_literal: true

module MiniTarball
  # Writes NUL bytes in chunks, so a large count doesn't allocate a large string.
  #
  # @api private
  module NullWriter
    CHUNK_SIZE = 65_536
    CHUNK = ("\0" * CHUNK_SIZE).freeze
    private_constant :CHUNK_SIZE, :CHUNK

    # @param io [IO] the IO stream to write to
    # @param count [Integer] number of null bytes to write
    # @return [void]
    def self.write(io, count)
      remaining = count
      while remaining > 0
        to_write = [remaining, CHUNK_SIZE].min
        # A full chunk is written as it is, so only the last write allocates a new string
        io.write(to_write == CHUNK_SIZE ? CHUNK : CHUNK.byteslice(0, to_write))
        remaining -= to_write
      end
    end
  end
end
