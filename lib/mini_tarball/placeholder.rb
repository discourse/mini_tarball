# frozen_string_literal: true

module MiniTarball
  PlaceholderRef =
    Data.define(
      :header_start_position,
      :file_start_position,
      :size,
      :writer_id,
    )
end
