# frozen_string_literal: true

require_relative "../../integration_helper"
require "open3"
require "zlib"

# Independently implemented scenarios from GNU tar 1.35's Autotest suite.
# Source mappings and deliberate differences are in README.md in this directory.
RSpec.shared_context "with a GNU tar Autotest workspace" do
  around do |example|
    Dir.mktmpdir("mini_tarball_autotest") do |dir|
      @work_dir = dir
      begin
        example.run
      ensure
        # Some scenarios restore read-only directories. Make only real directories
        # writable before cleanup; never follow symlinks created by a test.
        Dir
          .glob("#{dir}/**/*", File::FNM_DOTMATCH)
          .each { |path| File.chmod(0700, path) if File.directory?(path) && !File.symlink?(path) }
      end
    end
  end

  let(:work_dir) { @work_dir }
  let(:archive_path) { File.join(work_dir, "archive.tar") }
  let(:extract_dir) { FileUtils.mkdir_p(File.join(work_dir, "out")).first }

  def write_archive(&)
    MiniTarball::Writer.create(archive_path, &)
  end

  def run_tar(*arguments, stdin_data: "", status: 0)
    stdout, stderr, result =
      Open3.capture3(
        { "LC_ALL" => "C", "TZ" => "UTC", "TAR_OPTIONS" => nil },
        tar_binary,
        *arguments,
        stdin_data:,
        binmode: true,
      )
    expect(result.exitstatus).to eq(status), "#{tar_binary} #{arguments.inspect}: #{stderr}"
    stdout
  end

  def extract_archive(*options)
    run_tar("-xf", archive_path, "-C", extract_dir, *options)
  end

  def extracted(name)
    File.join(extract_dir, name)
  end

  # macOS limits paths to 1024 bytes and Linux to 4096. Longer names are still
  # written and listed correctly, but no tar can extract them on that system.
  def skip_unless_extractable(*names)
    path_max = RUBY_PLATFORM.include?("darwin") ? 1024 : 4096
    longest = names.map { |name| extracted(name).bytesize }.max
    return if longest < path_max

    skip "a path of #{longest} bytes doesn't fit the path limit of this system"
  end

  # Keep individual components short enough for the host filesystem.
  def archive_name(bytes)
    name = (("n" * 63 + "/") * (bytes / 64)) + ("f" * (bytes % 64))
    name.end_with?("/") ? "#{name.chop}f" : name
  end
end
