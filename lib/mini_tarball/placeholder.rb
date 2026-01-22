# frozen_string_literal: true

module MiniTarball
  class Placeholder
    attr_reader :header_start_position, :file_start_position, :size

    def initialize(writer:, header_start_position:, file_start_position:, size:)
      @writer = writer
      @header_start_position = header_start_position
      @file_start_position = file_start_position
      @size = size
      @filled = false
    end

    def fill(&block)
      raise ArgumentError, "Placeholder already filled" if @filled
      @writer.send(:fill_placeholder, self, &block)
      @filled = true
      @writer
    end

    def filled?
      @filled
    end
  end
end
