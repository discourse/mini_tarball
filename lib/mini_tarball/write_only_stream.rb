# frozen_string_literal: true

module MiniTarball
  class WriteOnlyStream
    def initialize(io)
      @io = io
    end

    def write(data)
      @io.write (data)
    end
  end
end
