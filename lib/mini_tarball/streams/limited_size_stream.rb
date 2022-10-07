# frozen_string_literal: true

module MiniTarball
  class WriteOutOfRangeError < StandardError; end

  class LimitedSizeStream
    attr_reader :start_position, :end_position

    def initialize(io, start_position:, max_file_size:)
      @io = io
      @start_position = start_position
      @end_position = start_position + max_file_size
    end

    def write(data)
      if @io.pos < start_position || @io.pos + data.bytesize > end_position
        raise WriteOutOfRangeError.new("Writing outside of limits not allowed")
      end

      @io.write(data)
    end
  end
end
