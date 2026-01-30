# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../support/gnu_tar"

class FixtureGenerator
  STANDARD_OPTIONS = {
    uname: "discourse",
    uid: 1001,
    gname: "www-data",
    gid: 33,
    mtime: "2021-02-15T20:11:34Z",
    mode: 0644,
  }.freeze

  DEFAULT_OUTPUT_DIR = File.expand_path(__dir__).freeze

  attr_reader :output_dir, :headers_dir, :files_dir, :archives_dir

  def initialize(output_dir: DEFAULT_OUTPUT_DIR)
    @output_dir = output_dir
    @headers_dir = File.join(output_dir, "headers")
    @files_dir = File.join(output_dir, "files")
    @archives_dir = File.join(output_dir, "archives")
  end

  def generate_all
    ensure_directories
    generate_headers
    generate_files
    generate_archives
  end

  def generate_headers
    # Use /var/tmp if available (usually disk-backed, not tmpfs) for large sparse files
    tmpdir_parent = File.directory?("/var/tmp") ? "/var/tmp" : nil
    Dir.mktmpdir("mini_tarball_fixtures", tmpdir_parent) do |tmpdir|
      Dir.chdir(tmpdir) do
        generate_small_file_header
        generate_large_file_header
        generate_long_filename_header
        generate_unicode_filename_header
        generate_long_unicode_filename_header
        generate_short_path_header
        generate_long_path_header
        generate_directory_header
        generate_symlink_short_target_header
        generate_symlink_long_target_header
        generate_hardlink_short_target_header
        generate_hardlink_long_target_header
        generate_exactly_100_byte_name_header
        generate_exactly_101_byte_name_header
        generate_empty_file_header
      end
    end
  end

  def generate_files
    generate_fixture_file("file1.txt", create_content(length: 1042))
    generate_fixture_file("file2.txt", create_content(length: 391))
    generate_fixture_file("file3.txt", create_content(length: 1063))
    generate_fixture_file(
      "file1_with_trailing_zeros.txt",
      create_content(length: 1042) + "\0" * 1492,
    )
  end

  def generate_archives
    Dir.mktmpdir do |tmpdir|
      FileUtils.cp(File.join(files_dir, "file1.txt"), tmpdir)
      FileUtils.cp(File.join(files_dir, "file2.txt"), tmpdir)
      FileUtils.cp(File.join(files_dir, "file3.txt"), tmpdir)

      generate_archive("multiple_files.tar", %w[file1.txt file2.txt file3.txt], tmpdir)

      FileUtils.cp(
        File.join(files_dir, "file1_with_trailing_zeros.txt"),
        File.join(tmpdir, "file1.txt"),
      )

      generate_archive("small_file_in_large_placeholder.tar", %w[file1.txt file2.txt], tmpdir)
    end
  end

  private

  def ensure_directories
    FileUtils.mkdir_p([headers_dir, files_dir, archives_dir])
  end

  def generate_small_file_header
    create_header("small_file", header_size: 512) do
      create_sparse_file("small_file", 536_870_913)
      ["small_file"]
    end
  end

  def generate_large_file_header
    create_header("large_file", header_size: 512) do
      create_sparse_file("large_file", 10_737_418_241)
      ["large_file"]
    end
  end

  def generate_long_filename_header
    create_header("long_filename", header_size: 1536) do
      name =
        "this_is_an_extremely_long_file_name_with_many_underscores_and_" \
          "lots_of_ascii_characters_in_it_and_will_be_used_to_test_gnu_tar.txt"
      create_file(name, "foo")
      [name]
    end
  end

  def generate_unicode_filename_header
    create_header("unicode_filename", header_size: 512) do
      name = "这是一个测试.txt"
      create_file(name, "foo")
      [name]
    end
  end

  def generate_long_unicode_filename_header
    create_header("long_unicode_filename", header_size: 1536) do
      name = "这是一个很长的中文句子，用于测试我们的实现在计算文件名长度时是否使用字节大小.txt"
      create_file(name, "foo")
      [name]
    end
  end

  def generate_short_path_header
    create_header("short_path", header_size: 512) do
      path = "this/is/a/short/path"
      FileUtils.mkdir_p(path)
      create_file(File.join(path, "test.txt"), "foo")
      [File.join(path, "test.txt")]
    end
  end

  def generate_long_path_header
    create_header("long_path", header_size: 1536) do
      path =
        "this/is/a/very/long/path/with/lots/of/sub/directories/to/test/how/gnu/tar/" \
          "behaves/when/files/are/stored/in/a/very/long/path"
      FileUtils.mkdir_p(path)
      create_file(File.join(path, "test.txt"), "foo")
      [File.join(path, "test.txt")]
    end
  end

  def generate_directory_header
    # Directories use mode 0755 by convention
    create_header("directory", header_size: 512, mode: 0755) do
      FileUtils.mkdir_p("testdir")
      ["testdir"]
    end
  end

  def generate_symlink_short_target_header
    create_header("symlink_short_target", header_size: 512) do
      create_file("target.txt", "foo")
      File.symlink("target.txt", "link.txt")
      ["link.txt"]
    end
  end

  def generate_symlink_long_target_header
    create_header("symlink_long_target", header_size: 1536) do
      long_target =
        "this/is/a/very/long/path/with/lots/of/sub/directories/to/test/how/gnu/tar/" \
          "behaves/when/symlinks/point/to/a/very/long/target/path.txt"
      FileUtils.mkdir_p(File.dirname(long_target))
      create_file(long_target, "foo")
      File.symlink(long_target, "link.txt")
      ["link.txt"]
    end
  end

  def generate_hardlink_short_target_header
    # Skip past original file: file header (512) + data padded to 512 = 1024 bytes
    create_header("hardlink_short_target", header_size: 512, offset: 1024) do
      create_file("original.txt", "foo")
      File.link("original.txt", "hardlink.txt")
      %w[original.txt hardlink.txt]
    end
  end

  def generate_hardlink_long_target_header
    # For hardlink with long target, we need to skip past the original file's headers
    # to get to the hardlink entry. The original file (with long name) takes:
    # LongLink header (512) + name data (512) + file header (512) + data (512) = 2048 bytes
    create_header("hardlink_long_target", header_size: 1536, offset: 2048) do
      long_name =
        "this_is_an_extremely_long_file_name_with_many_underscores_and_" \
          "lots_of_ascii_characters_that_exceeds_one_hundred_bytes.txt"
      create_file(long_name, "foo")
      File.link(long_name, "hardlink.txt")
      [long_name, "hardlink.txt"]
    end
  end

  def generate_exactly_100_byte_name_header
    create_header("exactly_100_byte_name", header_size: 512) do
      # 100 bytes exactly: no LongLink extension needed
      name = "a" * 96 + ".txt"
      create_file(name, "foo")
      [name]
    end
  end

  def generate_exactly_101_byte_name_header
    create_header("exactly_101_byte_name", header_size: 1536) do
      # 101 bytes: LongLink extension required
      name = "a" * 97 + ".txt"
      create_file(name, "foo")
      [name]
    end
  end

  def generate_empty_file_header
    create_header("empty_file", header_size: 512) do
      create_file("empty.txt", "")
      ["empty.txt"]
    end
  end

  def create_header(name, header_size:, sparse: false, offset: 0, **overrides)
    # Use a subdirectory for each header to avoid filename conflicts
    Dir.mkdir(name)
    Dir.chdir(name) do
      files = yield
      tar_path = "#{name}.tar"

      options = STANDARD_OPTIONS.merge(overrides)
      GnuTar.create(tar_path, files:, chdir: ".", sparse:, **options)

      File.open(tar_path, "rb") do |f|
        f.seek(offset) if offset > 0
        header_data = f.read(header_size)
        File.binwrite(File.join(headers_dir, "#{name}_header"), header_data)
      end

      puts "Generated #{name}_header"
    end
    FileUtils.rm_rf(name)
  end

  def generate_fixture_file(name, content)
    File.binwrite(File.join(files_dir, name), content)
    puts "Generated #{name}"
  end

  def generate_archive(name, files, chdir)
    GnuTar.create(
      File.join(archives_dir, name),
      files:,
      chdir:,
      blocking_factor: 1,
      **STANDARD_OPTIONS,
    )
    puts "Generated #{name}"
  end

  def create_file(path, content)
    File.binwrite(path, content)
    path
  end

  def create_sparse_file(path, size)
    FileUtils.touch(path)
    File.truncate(path, size)
    path
  end

  def create_content(length:)
    index = 0
    content = +""
    chars = ("a".."z").to_a

    while index < length / 16
      content << chars[index % chars.size] * 16
      index += 1
    end

    if (remainder = length % 16) > 0
      content << chars[index % chars.size] * remainder
    end

    content << "\n"
    content
  end
end
