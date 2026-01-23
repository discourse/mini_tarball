# frozen_string_literal: true

module MiniTarball
  class CappedWriteStream
    attr_reader :bytes_written

    def initialize(io, max_size:)
      @io = io
      @max_size = max_size
      @bytes_written = 0
    end

    def write(data)
      new_total = @bytes_written + data.bytesize

      raise WriteOutOfRangeError if new_total > @max_size

      result = @io.write(data)
      @bytes_written += data.bytesize
      result
    end

    def <<(data)
      write(data)
      self
    end

    def remaining
      @max_size - @bytes_written
    end
  end
end
