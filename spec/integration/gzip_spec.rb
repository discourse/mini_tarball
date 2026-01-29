# frozen_string_literal: true

require_relative "../integration_helper"
require "zlib"
require "tmpdir"

RSpec.describe "Gzip compression" do
  it "creates a valid tar.gz archive" do
    Dir.mktmpdir do |tmpdir|
      archive_path = File.join(tmpdir, "test.tar.gz")
      extract_dir = File.join(tmpdir, "extracted")
      FileUtils.mkdir_p(extract_dir)

      content = "Hello from gzipped tar!"
      Zlib::GzipWriter.open(archive_path) do |gz|
        MiniTarball::Writer.use(gz) do |tar|
          tar.add_file_from_stream(
            name: "hello.txt",
            size: content.bytesize,
            mtime: Time.utc(2024, 1, 1),
          ) { |io| io.write(content) }
        end
      end

      success =
        system(
          GnuTar.binary_path,
          "-xzf",
          archive_path,
          "-C",
          extract_dir,
          out: File::NULL,
          err: File::NULL,
        )

      expect(success).to be true
      expect(File.join(extract_dir, "hello.txt")).to be_file(content:)
    end
  end

  it "creates a tar.gz with multiple entries" do
    Dir.mktmpdir do |tmpdir|
      archive_path = File.join(tmpdir, "multi.tar.gz")
      extract_dir = File.join(tmpdir, "extracted")
      FileUtils.mkdir_p(extract_dir)

      Zlib::GzipWriter.open(archive_path) do |gz|
        MiniTarball::Writer.use(gz) do |tar|
          tar.add_directory(name: "mydir", mtime: Time.utc(2024, 1, 1))
          tar.add_file_from_stream(
            name: "mydir/a.txt",
            size: 5,
            mtime: Time.utc(2024, 1, 1),
          ) { |io| io.write("aaaaa") }
          tar.add_file_from_stream(
            name: "mydir/b.txt",
            size: 5,
            mtime: Time.utc(2024, 1, 1),
          ) { |io| io.write("bbbbb") }
        end
      end

      success =
        system(
          GnuTar.binary_path,
          "-xzf",
          archive_path,
          "-C",
          extract_dir,
          out: File::NULL,
          err: File::NULL,
        )

      expect(success).to be true
      expect(File.join(extract_dir, "mydir")).to be_dir
      expect(File.join(extract_dir, "mydir/a.txt")).to be_file(content: "aaaaa")
      expect(File.join(extract_dir, "mydir/b.txt")).to be_file(content: "bbbbb")
    end
  end
end
