# frozen_string_literal: true

module GnuTar
  MINIMUM_VERSION = "1.26"

  class << self
    def available?
      path = binary_path
      return false unless path

      version_string = version
      return false unless version_string

      Gem::Version.new(version_string) >= Gem::Version.new(MINIMUM_VERSION)
    end

    def binary_path
      @binary_path ||= detect_binary
    end

    def version
      path = binary_path
      return unless path

      @version ||= parse_version(`#{path} --version 2>&1`)
    end

    def skip_message
      "GNU tar #{MINIMUM_VERSION}+ not found. Install with: brew install gnu-tar (macOS) or apt install tar (Linux)"
    end

    def create(archive_path, files:, chdir:, sparse: false, **options)
      raise "GNU tar not available" unless available?

      args = ["-cf", archive_path, "--format=gnu"]
      args += ["--sparse"] if sparse
      unless options[:uid].nil?
        owner = options[:uname] ? "#{options[:uname]}:#{options[:uid]}" : options[:uid].to_s
        args += ["--owner=#{owner}"]
      end
      unless options[:gid].nil?
        group = options[:gname] ? "#{options[:gname]}:#{options[:gid]}" : options[:gid].to_s
        args += ["--group=#{group}"]
      end
      args += ["--mtime=#{options[:mtime]}"] if options[:mtime]
      args += ["--mode=#{format("%04o", options[:mode])}"] unless options[:mode].nil?
      args += ["--blocking-factor=#{options[:blocking_factor]}"] if options[:blocking_factor]
      args += files

      Dir.chdir(chdir) { system(binary_path, *args, out: File::NULL, err: File::NULL) }
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
