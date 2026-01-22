# frozen_string_literal: true

module MiniTarball
  class WriteOutOfRangeError < StandardError
  end

  class LimitedSizeStream
    attr_reader :start_position, :end_position
    private attr_reader :io

    def initialize(io, start_position:, max_file_size:)
      @io = io
      @start_position = start_position
      @end_position = start_position + max_file_size
    end

    def write(data)
      current_position = io.pos

      if current_position < start_position || current_position + data.bytesize > end_position
        raise WriteOutOfRangeError.new("Writing outside of limits not allowed")
      end

      io.write(data)
    end

    def <<(data)
      write(data)
      self
    end
  end
end
