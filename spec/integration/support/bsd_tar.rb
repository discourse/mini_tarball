# frozen_string_literal: true

require "open3"

module BsdTar
  COMMAND = "bsdtar"

  class << self
    def available?
      !!binary_path
    end

    def binary_path
      return @binary_path if defined?(@binary_path)

      output, status = Open3.capture2e(COMMAND, "--version")
      @binary_path = status.success? && output.include?("bsdtar") ? COMMAND : nil
    end
  end
end
