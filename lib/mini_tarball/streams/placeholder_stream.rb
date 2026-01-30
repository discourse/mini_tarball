# frozen_string_literal: true

module MiniTarball
  # A stream for writing placeholder content with automatic null-padding.
  # Fills any remaining space in the region with null bytes after each write.
  #
  # @api private
  class PlaceholderStream < BoundedRegionStream
    # Writes data and pads remaining space with null bytes.
    #
    # @param data [String] data to write
    # @return [Integer] number of bytes written (excluding padding)
    # @raise [WriteOutOfRangeError] if write would exceed the allowed region
    def write(data)
      written = super(data)

      current_position = io.pos
      remaining = end_position - current_position
      io.write("\0" * remaining) if remaining > 0

      written
    end
  end
end
