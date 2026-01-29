# frozen_string_literal: true

module GnuTar
  MINIMUM_VERSION = "1.26"

  class << self
    def available?
      !!binary_path
    end

    def binary_path
      @binary_path ||= detect_binary
    end

    def version
      return unless available?

      @version ||= parse_version(`#{binary_path} --version 2>&1`)
    end

    def skip_message
      "GNU tar #{MINIMUM_VERSION}+ not found. Install with: brew install gnu-tar (macOS) or apt install tar (Linux)"
    end

    def extract(archive_path, destination:)
      raise "GNU tar not available" unless available?

      system(binary_path, "-xf", archive_path, "-C", destination, out: File::NULL, err: File::NULL)
    end

    def list(archive_path)
      raise "GNU tar not available" unless available?

      `#{binary_path} -tf #{archive_path} 2>&1`.lines.map(&:chomp)
    end

    private

    def detect_binary
      # Try gtar first (macOS Homebrew), then tar
      %w[gtar tar].each do |cmd|
        path = `which #{cmd} 2>/dev/null`.chomp
        next if path.empty?

        output = `#{path} --version 2>&1`
        return path if output.include?("GNU tar")
      end

      nil
    end

    def parse_version(output)
      match = output.match(/GNU tar.*?(\d+\.\d+)/)
      match ? match[1] : nil
    end
  end
end
