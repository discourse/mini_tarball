# frozen_string_literal: true

module BsdTar
  class << self
    def available?
      !!binary_path
    end

    def binary_path
      @binary_path ||= detect_binary
    end

    private

    def detect_binary
      path = `which bsdtar 2>/dev/null`.chomp
      return nil if path.empty?

      output = `#{path} --version 2>&1`
      return path if output.include?("bsdtar")

      nil
    end
  end
end
