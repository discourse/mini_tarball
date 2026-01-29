# frozen_string_literal: true

module MiniTarball
  # An opaque reference to a reserved placeholder in the archive.
  # Returned by {Writer#reserve} and passed to {Writer#fill}.
  #
  # @!attribute [r] size
  #   @return [Integer] the reserved size in bytes
  PlaceholderRef = Data.define(:header_start_position, :file_start_position, :size, :writer_id)
end
