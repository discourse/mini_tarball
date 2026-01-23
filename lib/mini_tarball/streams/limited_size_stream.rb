# frozen_string_literal: true

module MiniTarball
  class WriteOutOfRangeError < StandardError
    def initialize(msg = "Write exceeds allowed size")
      super
    end
  end

  class LimitedSizeStream
    attr_reader :start_position, :end_position
    private attr_reader :io

    def initialize(io, start_position:, size:)
      @io = io
      @start_position = start_position
      @end_position = start_position + size
    end

    def write(data)
      current_position = io.pos

      if current_position < start_position || current_position + data.bytesize > end_position
        raise WriteOutOfRangeError
      end

      io.write(data)
    end

    def <<(data)
      write(data)
      self
    end
  end
end
