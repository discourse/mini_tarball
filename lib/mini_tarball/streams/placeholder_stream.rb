# frozen_string_literal: true

module MiniTarball
  class PlaceholderStream < LimitedSizeStream
    def initialize(io, start_position:, file_size:)
      super(io, start_position: start_position, max_file_size: file_size)
    end

    def write(data)
      super(data)
      @io.write("\0" * (end_position - @io.pos)) if @io.pos <= end_position
    end
  end
end
