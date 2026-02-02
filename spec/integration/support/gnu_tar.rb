# frozen_string_literal: true

require "open3"

module GnuTar
  MINIMUM_VERSION = "1.26"
  COMMANDS = %w[gtar tar].freeze

  class << self
    def available?
      !!(binary_path && version && Gem::Version.new(version) >= Gem::Version.new(MINIMUM_VERSION))
    end

    def binary_path
      @binary_path ||= detect_binary
    end

    def version
      @version ||= detect_version
    end

    def skip_message
      "GNU tar #{MINIMUM_VERSION}+ not found"
    end

    def create(archive_path, files:, chdir:, sparse: false, **options)
      args = ["-cf", archive_path, "--format=gnu"]
      args << "--sparse" if sparse
      args << "--owner=#{format_owner(options)}" if options[:uid]
      args << "--group=#{format_group(options)}" if options[:gid]
      args << "--mtime=#{options[:mtime]}" if options[:mtime]
      args << "--mode=#{format("%04o", options[:mode])}" if options[:mode]
      args << "--blocking-factor=#{options[:blocking_factor]}" if options[:blocking_factor]
      args.concat(files)

      Dir.chdir(chdir) { system(binary_path, *args, out: File::NULL, err: File::NULL) }
    end

    def extract(archive_path, destination:)
      system(binary_path, "-xf", archive_path, "-C", destination, out: File::NULL, err: File::NULL)
    end

    private

    def detect_binary
      COMMANDS.find do |cmd|
        output, status = Open3.capture2e(cmd, "--version")
        status.success? && output.include?("GNU tar")
      rescue Errno::ENOENT
        false
      end
    end

    def detect_version
      return unless binary_path

      output, _status = Open3.capture2(binary_path, "--version")
      match = output.match(/GNU tar.*?(\d+\.\d+)/)
      match[1] if match
    end

    def format_owner(options)
      options[:uname] ? "#{options[:uname]}:#{options[:uid]}" : options[:uid].to_s
    end

    def format_group(options)
      options[:gname] ? "#{options[:gname]}:#{options[:gid]}" : options[:gid].to_s
    end
  end
end
