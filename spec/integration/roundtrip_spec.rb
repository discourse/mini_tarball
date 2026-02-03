# frozen_string_literal: true

require_relative "../integration_helper"
require "tmpdir"

RSpec.describe "Writer/Reader roundtrip" do
  let(:tmpdir) { Dir.mktmpdir("roundtrip_test") }

  after { FileUtils.rm_rf(tmpdir) }

  describe "files" do
    it "roundtrips file content" do
      io = StringIO.new(String.new, "w+b")
      content = "Hello, roundtrip world!"

      MiniTarball::Writer.use(io) { |writer| writer.file "test.txt", content: }

      io.reopen(io.string, "rb")
      read_content = nil
      MiniTarball::Reader.use(io) do |reader|
        reader.each_file { |_, stream| read_content = stream.read }
      end

      expect(read_content).to eq(content)
    end

    it "roundtrips file metadata" do
      io = StringIO.new(String.new, "w+b")
      mtime = Time.utc(2023, 6, 15, 10, 30, 0)

      MiniTarball::Writer.use(io) do |writer|
        writer.file "test.txt",
                    content: "content",
                    mode: 0755,
                    uid: 1000,
                    gid: 1000,
                    uname: "testuser",
                    gname: "testgroup",
                    mtime:
      end

      io.reopen(io.string, "rb")
      entry = nil
      MiniTarball::Reader.use(io) { |reader| reader.each_file { |e, _| entry = e } }

      expect(entry.name).to eq("test.txt")
      expect(entry.mode).to eq(0755)
      expect(entry.uid).to eq(1000)
      expect(entry.gid).to eq(1000)
      expect(entry.uname).to eq("testuser")
      expect(entry.gname).to eq("testgroup")
      expect(entry.mtime.to_i).to eq(mtime.to_i)
    end

    it "roundtrips multiple files" do
      io = StringIO.new(String.new, "w+b")
      files = {
        "file1.txt" => "Content one",
        "file2.txt" => "Content two",
        "file3.txt" => "Content three",
      }

      MiniTarball::Writer.use(io) do |writer|
        files.each { |name, content| writer.file name, content: }
      end

      io.reopen(io.string, "rb")
      read_files = {}
      MiniTarball::Reader.use(io) do |reader|
        reader.each_file { |entry, stream| read_files[entry.name] = stream.read }
      end

      expect(read_files).to eq(files)
    end

    it "roundtrips binary content" do
      io = StringIO.new(String.new, "w+b")
      binary_content = (0..255).to_a.pack("C*")

      MiniTarball::Writer.use(io) { |writer| writer.file "binary.bin", content: binary_content }

      io.reopen(io.string, "rb")
      read_content = nil
      MiniTarball::Reader.use(io) do |reader|
        reader.each_file { |_, stream| read_content = stream.read }
      end

      expect(read_content).to eq(binary_content)
    end

    it "roundtrips files with long names" do
      io = StringIO.new(String.new, "w+b")
      long_name = "a" * 150 + ".txt"

      MiniTarball::Writer.use(io) { |writer| writer.file long_name, content: "long name content" }

      io.reopen(io.string, "rb")
      entry_name = nil
      MiniTarball::Reader.use(io) do |reader|
        reader.each_file { |entry, _| entry_name = entry.name }
      end

      expect(entry_name).to eq(long_name)
    end
  end

  describe "directories" do
    it "roundtrips directory entries" do
      io = StringIO.new(String.new, "w+b")

      MiniTarball::Writer.use(io) { |writer| writer.directory "mydir/", mode: 0755 }

      io.reopen(io.string, "rb")
      entry = nil
      MiniTarball::Reader.use(io) { |reader| reader.each_entry { |e, _| entry = e } }

      expect(entry.name).to eq("mydir/")
      expect(entry.directory?).to be true
      expect(entry.mode).to eq(0755)
    end
  end

  describe "symlinks" do
    it "roundtrips symlink entries" do
      io = StringIO.new(String.new, "w+b")

      MiniTarball::Writer.use(io) do |writer|
        writer.file "target.txt", content: "target"
        writer.symlink "link.txt", target: "target.txt"
      end

      io.reopen(io.string, "rb")
      symlink = nil
      MiniTarball::Reader.use(io) do |reader|
        reader.each_entry { |entry, _| symlink = entry if entry.symlink? }
      end

      expect(symlink.name).to eq("link.txt")
      expect(symlink.linkname).to eq("target.txt")
    end

    it "roundtrips symlinks with long targets" do
      io = StringIO.new(String.new, "w+b")
      long_target = "path/" * 25 + "target.txt"

      MiniTarball::Writer.use(io) do |writer|
        writer.file long_target, content: "target"
        writer.symlink "link.txt", target: long_target
      end

      io.reopen(io.string, "rb")
      symlink = nil
      MiniTarball::Reader.use(io) do |reader|
        reader.each_entry { |entry, _| symlink = entry if entry.symlink? }
      end

      expect(symlink.linkname).to eq(long_target)
    end
  end

  describe "hardlinks" do
    it "roundtrips hardlink entries" do
      io = StringIO.new(String.new, "w+b")

      MiniTarball::Writer.use(io) do |writer|
        writer.file "original.txt", content: "original"
        writer.hardlink "hardlink.txt", target: "original.txt"
      end

      io.reopen(io.string, "rb")
      hardlink = nil
      MiniTarball::Reader.use(io) do |reader|
        reader.each_entry { |entry, _| hardlink = entry if entry.hardlink? }
      end

      expect(hardlink.name).to eq("hardlink.txt")
      expect(hardlink.linkname).to eq("original.txt")
    end
  end

  describe "extraction roundtrip" do
    it "extracts what was written" do
      io = StringIO.new(String.new, "w+b")
      extract_dir = File.join(tmpdir, "extracted")
      FileUtils.mkdir_p(extract_dir)

      MiniTarball::Writer.use(io) do |writer|
        writer.directory "subdir/"
        writer.file "subdir/file.txt", content: "Nested content"
        writer.file "root.txt", content: "Root content"
      end

      io.reopen(io.string, "rb")
      MiniTarball::Reader.use(io) { |reader| reader.extract_all(extract_dir) }

      expect(File.directory?(File.join(extract_dir, "subdir"))).to be true
      expect(File.read(File.join(extract_dir, "subdir", "file.txt"))).to eq("Nested content")
      expect(File.read(File.join(extract_dir, "root.txt"))).to eq("Root content")
    end
  end

  describe "compatibility with external tools" do
    let(:archive_path) { File.join(tmpdir, "test.tar") }
    let(:extract_dir) { File.join(tmpdir, "extracted") }

    before { FileUtils.mkdir_p(extract_dir) }

    it "archives written by Writer can be extracted by GNU tar" do
      File.open(archive_path, "wb") do |f|
        MiniTarball::Writer.use(f) do |writer|
          writer.file "test.txt", content: "Hello from MiniTarball!"
        end
      end

      # Extract with GNU tar
      expect(GnuTar.extract(archive_path, destination: extract_dir)).to be true
      expect(File.read(File.join(extract_dir, "test.txt"))).to eq("Hello from MiniTarball!")
    end

    it "archives created by GNU tar can be read by Reader" do
      source_dir = File.join(tmpdir, "source")
      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "test.txt"), "Hello from GNU tar!")

      GnuTar.create(archive_path, files: ["test.txt"], chdir: source_dir)

      content = nil
      MiniTarball::Reader.open(archive_path) do |reader|
        reader.each_file { |_, stream| content = stream.read }
      end

      expect(content).to eq("Hello from GNU tar!")
    end
  end
end
