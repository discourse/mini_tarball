# frozen_string_literal: true

require_relative "../integration_helper"
require "zlib"
require "tmpdir"

RSpec.describe "Gzip compression" do
  it "creates a valid tar.gz archive" do
    Dir.mktmpdir do |tmpdir|
      archive_path = File.join(tmpdir, "test.tar.gz")

      content = "Hello from gzipped tar!"
      Zlib::GzipWriter.open(archive_path) do |gz|
        MiniTarball::Writer.use(gz) do |tar|
          tar.file "hello.txt", size: content.bytesize, mtime: Time.utc(2024, 1, 1) do |io|
            io.write(content)
          end
        end
      end

      TarExtractor.each_extractor do |extractor|
        extract_dir = File.join(tmpdir, "extracted_#{extractor.name.tr(" ", "_")}")
        FileUtils.mkdir_p(extract_dir)
        success =
          TarExtractor.extract(archive_path, destination: extract_dir, extractor:, gzip: true)

        expect(success).to be true
        expect(File.join(extract_dir, "hello.txt")).to be_file(content:)
      end
    end
  end

  it "creates a tar.gz with multiple entries" do
    Dir.mktmpdir do |tmpdir|
      archive_path = File.join(tmpdir, "multi.tar.gz")

      Zlib::GzipWriter.open(archive_path) do |gz|
        MiniTarball::Writer.use(gz) do |tar|
          tar.directory "mydir", mtime: Time.utc(2024, 1, 1)
          tar.file("mydir/a.txt", size: 5, mtime: Time.utc(2024, 1, 1)) { |io| io.write("aaaaa") }
          tar.file("mydir/b.txt", size: 5, mtime: Time.utc(2024, 1, 1)) { |io| io.write("bbbbb") }
        end
      end

      TarExtractor.each_extractor do |extractor|
        extract_dir = File.join(tmpdir, "extracted_#{extractor.name.tr(" ", "_")}")
        FileUtils.mkdir_p(extract_dir)
        success =
          TarExtractor.extract(archive_path, destination: extract_dir, extractor:, gzip: true)

        expect(success).to be true
        expect(File.join(extract_dir, "mydir")).to be_dir
        expect(File.join(extract_dir, "mydir/a.txt")).to be_file(content: "aaaaa")
        expect(File.join(extract_dir, "mydir/b.txt")).to be_file(content: "bbbbb")
      end
    end
  end
end
