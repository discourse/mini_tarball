# frozen_string_literal: true

module MiniTarball
  class PlaceholderStream < LimitedSizeStream
    def initialize(io, start_position:, file_size:)
      super(io, start_position: start_position, max_file_size: file_size)
    end

    def write(data)
      super(data)

      if (current_position = io.pos) <= end_position
        io.write("\0" * (end_position - current_position))
      end
    end
  end
end
