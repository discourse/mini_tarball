# frozen_string_literal: true

module MiniTarball
  class BoundedReadStream
    def initialize(io, size:)
      @io = io
      @remaining = size
    end

    def read(length = nil, buffer = nil)
      return nil if @remaining == 0

      length = @remaining if length.nil? || length > @remaining
      data = @io.read(length, buffer)
      @remaining -= data.bytesize if data
      data
    end

    def eof?
      @remaining == 0
    end

    attr_reader :remaining
  end
end
