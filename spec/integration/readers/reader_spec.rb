# frozen_string_literal: true

require_relative "../../integration_helper"
require "tmpdir"

RSpec.describe "Reader integration" do
  describe "extracting archives created by GNU tar" do
    let(:tmpdir) { Dir.mktmpdir("reader_integration") }
    let(:extract_dir) { File.join(tmpdir, "extracted") }

    before { FileUtils.mkdir_p(extract_dir) }
    after { FileUtils.rm_rf(tmpdir) }

    it "extracts files from GNU tar archives" do
      # Create a test archive using GNU tar
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "test.txt"), "Hello, World!")
      File.write(File.join(source_dir, "another.txt"), "Another file")

      archive_path = File.join(tmpdir, "test.tar")
      GnuTar.create(archive_path, files: %w[test.txt another.txt], chdir: source_dir)

      # Extract using our Reader
      MiniTarball::Reader.open(archive_path) { |reader| reader.extract_all(extract_dir) }

      expect(File.read(File.join(extract_dir, "test.txt"))).to eq("Hello, World!")
      expect(File.read(File.join(extract_dir, "another.txt"))).to eq("Another file")
    end

    it "handles files with long names (>100 bytes)" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)

      long_name = "a" * 120 + ".txt"
      File.write(File.join(source_dir, long_name), "Long name content")

      archive_path = File.join(tmpdir, "long_name.tar")
      GnuTar.create(archive_path, files: [long_name], chdir: source_dir)

      MiniTarball::Reader.open(archive_path) { |reader| reader.extract_all(extract_dir) }

      expect(File.read(File.join(extract_dir, long_name))).to eq("Long name content")
    end

    it "handles deep directory structures" do
      source_dir = File.join(tmpdir, "source")
      deep_path = "a/b/c/d/e/f/g"
      FileUtils.mkdir_p(File.join(source_dir, deep_path))
      File.write(File.join(source_dir, deep_path, "deep.txt"), "Deep file")

      archive_path = File.join(tmpdir, "deep.tar")
      GnuTar.create(archive_path, files: [File.join(deep_path, "deep.txt")], chdir: source_dir)

      MiniTarball::Reader.open(archive_path) { |reader| reader.extract_all(extract_dir) }

      expect(File.read(File.join(extract_dir, deep_path, "deep.txt"))).to eq("Deep file")
    end

    it "handles symlinks" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "target.txt"), "Target content")
      File.symlink("target.txt", File.join(source_dir, "link.txt"))

      archive_path = File.join(tmpdir, "symlink.tar")
      GnuTar.create(archive_path, files: %w[target.txt link.txt], chdir: source_dir)

      MiniTarball::Reader.open(archive_path) { |reader| reader.extract_all(extract_dir) }

      link_path = File.join(extract_dir, "link.txt")
      expect(File.symlink?(link_path)).to be true
      expect(File.readlink(link_path)).to eq("target.txt")
    end

    it "handles hardlinks" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "original.txt"), "Original content")
      File.link(File.join(source_dir, "original.txt"), File.join(source_dir, "hardlink.txt"))

      archive_path = File.join(tmpdir, "hardlink.tar")
      GnuTar.create(archive_path, files: %w[original.txt hardlink.txt], chdir: source_dir)

      MiniTarball::Reader.open(archive_path) { |reader| reader.extract_all(extract_dir) }

      original_path = File.join(extract_dir, "original.txt")
      hardlink_path = File.join(extract_dir, "hardlink.txt")

      expect(File.stat(original_path).ino).to eq(File.stat(hardlink_path).ino)
    end

    it "handles directories" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(File.join(source_dir, "mydir"))
      File.write(File.join(source_dir, "mydir", "file.txt"), "Content")

      archive_path = File.join(tmpdir, "dir.tar")
      GnuTar.create(archive_path, files: %w[mydir mydir/file.txt], chdir: source_dir)

      MiniTarball::Reader.open(archive_path) { |reader| reader.extract_all(extract_dir) }

      expect(File.directory?(File.join(extract_dir, "mydir"))).to be true
      expect(File.read(File.join(extract_dir, "mydir", "file.txt"))).to eq("Content")
    end

    it "handles unicode filenames" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)

      unicode_name = "日本語ファイル.txt"
      File.write(File.join(source_dir, unicode_name), "Unicode content")

      archive_path = File.join(tmpdir, "unicode.tar")
      GnuTar.create(archive_path, files: [unicode_name], chdir: source_dir)

      MiniTarball::Reader.open(archive_path) { |reader| reader.extract_all(extract_dir) }

      expect(File.read(File.join(extract_dir, unicode_name))).to eq("Unicode content")
    end
  end

  describe "reading entry metadata" do
    let(:tmpdir) { Dir.mktmpdir("reader_metadata") }

    after { FileUtils.rm_rf(tmpdir) }

    it "reads correct file size" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "test.txt"), "x" * 12_345)

      archive_path = File.join(tmpdir, "test.tar")
      GnuTar.create(archive_path, files: ["test.txt"], chdir: source_dir)

      sizes = []
      MiniTarball::Reader.open(archive_path) do |reader|
        reader.each_entry { |entry, _| sizes << entry.size }
      end

      expect(sizes).to include(12_345)
    end

    it "reads file permissions" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "test.txt"), "content")
      File.chmod(0755, File.join(source_dir, "test.txt"))

      archive_path = File.join(tmpdir, "test.tar")
      GnuTar.create(archive_path, files: ["test.txt"], chdir: source_dir)

      modes = []
      MiniTarball::Reader.open(archive_path) do |reader|
        reader.each_entry { |entry, _| modes << (entry.mode & 0o7777) }
      end

      expect(modes).to include(0755)
    end
  end

  describe "streaming" do
    let(:tmpdir) { Dir.mktmpdir("reader_streaming") }

    after { FileUtils.rm_rf(tmpdir) }

    it "streams file content without buffering entire file" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)

      # Create a reasonably sized file
      File.write(File.join(source_dir, "data.txt"), "x" * 100_000)

      archive_path = File.join(tmpdir, "test.tar")
      GnuTar.create(archive_path, files: ["data.txt"], chdir: source_dir)

      bytes_read = 0
      MiniTarball::Reader.open(archive_path) do |reader|
        reader.each_file do |entry, stream|
          # Read in small chunks
          while (chunk = stream.read(1024))
            bytes_read += chunk.bytesize
          end
        end
      end

      expect(bytes_read).to eq(100_000)
    end
  end
end
