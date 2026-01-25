# frozen_string_literal: true

require "tmpdir"

RSpec.describe MiniTarball::Reader do
  def create_tar
    io = StringIO.new.binmode
    MiniTarball::Writer.use(io) do |writer|
      writer.add_file_from_stream(name: "hello.txt") { |s| s.write("Hello!") }
      writer.add_file_from_stream(name: "world.txt") { |s| s.write("World!") }
    end
    StringIO.new(io.string).binmode
  end

  describe ".use" do
    it "yields a reader and closes it" do
      tar_io = create_tar
      reader = nil

      described_class.use(tar_io) { |r| reader = r }

      expect { reader.each_entry {} }.to raise_error(/closed/)
    end
  end

  describe "#each_entry" do
    it "iterates over entries" do
      tar_io = create_tar
      entries = []

      described_class.use(tar_io) do |reader|
        reader.each_entry { |entry, _| entries << entry.name }
      end

      expect(entries).to eq(%w[hello.txt world.txt])
    end

    it "provides content stream for each entry" do
      tar_io = create_tar
      contents = {}

      described_class.use(tar_io) do |reader|
        reader.each_entry { |entry, stream| contents[entry.name] = stream.read }
      end

      expect(contents["hello.txt"]).to eq("Hello!")
      expect(contents["world.txt"]).to eq("World!")
    end

    it "returns an enumerator without block" do
      tar_io = create_tar
      reader = described_class.new(tar_io)

      enum = reader.each_entry
      expect(enum).to be_a(Enumerator)

      entry, stream = enum.next
      expect(entry.name).to eq("hello.txt")
      expect(stream.read).to eq("Hello!")
    end

    it "handles partial reads correctly" do
      tar_io = create_tar
      contents = {}

      described_class.use(tar_io) do |reader|
        reader.each_entry do |entry, stream|
          # Only read first 3 bytes
          contents[entry.name] = stream.read(3)
        end
      end

      expect(contents["hello.txt"]).to eq("Hel")
      expect(contents["world.txt"]).to eq("Wor")
    end

    it "handles entries with long names" do
      io = StringIO.new.binmode
      long_name = "a" * 150 + ".txt"
      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: long_name) { |s| s.write("content") }
      end

      tar_io = StringIO.new(io.string).binmode
      entries = []

      described_class.use(tar_io) do |reader|
        reader.each_entry { |entry, _| entries << entry.name }
      end

      expect(entries).to eq([long_name])
    end

    it "handles symlinks with long targets" do
      io = StringIO.new.binmode
      long_target = "path/to/" + "a" * 150 + ".txt"
      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: long_target) { |s| s.write("content") }
        writer.add_symlink(name: "link.txt", target: long_target)
      end

      tar_io = StringIO.new(io.string).binmode
      symlink_entry = nil

      described_class.use(tar_io) do |reader|
        reader.each_entry { |entry, _| symlink_entry = entry if entry.symlink? }
      end

      expect(symlink_entry).not_to be_nil
      expect(symlink_entry.linkname).to eq(long_target)
    end

    it "handles directories" do
      io = StringIO.new.binmode
      MiniTarball::Writer.use(io) do |writer|
        writer.add_directory(name: "mydir")
        writer.add_file_from_stream(name: "mydir/file.txt") { |s| s.write("inside") }
      end

      tar_io = StringIO.new(io.string).binmode
      entries = []

      described_class.use(tar_io) do |reader|
        reader.each_entry { |entry, _| entries << [entry.name, entry.directory?] }
      end

      expect(entries).to eq([["mydir/", true], ["mydir/file.txt", false]])
    end

    it "returns self for chaining" do
      tar_io = create_tar
      reader = described_class.new(tar_io)

      result = reader.each_entry {}

      expect(result).to be(reader)
    end
  end

  describe "#close" do
    it "prevents further iteration" do
      tar_io = create_tar
      reader = described_class.new(tar_io)
      reader.close

      expect { reader.each_entry {} }.to raise_error(/closed/)
    end

    it "raises error when called twice" do
      tar_io = create_tar
      reader = described_class.new(tar_io)
      reader.close

      expect { reader.close }.to raise_error(/closed/)
    end
  end

  describe "#extract_all" do
    let(:tmpdir) { Dir.mktmpdir }
    after { FileUtils.rm_rf(tmpdir) }

    it "extracts files to destination" do
      tar_io = create_tar

      described_class.use(tar_io) { |reader| reader.extract_all(tmpdir) }

      expect(File.read(File.join(tmpdir, "hello.txt"))).to eq("Hello!")
      expect(File.read(File.join(tmpdir, "world.txt"))).to eq("World!")
    end

    it "extracts directories" do
      io = StringIO.new.binmode
      MiniTarball::Writer.use(io) do |writer|
        writer.add_directory(name: "subdir", mode: 0755)
        writer.add_file_from_stream(name: "subdir/file.txt") { |s| s.write("nested") }
      end

      tar_io = StringIO.new(io.string).binmode
      described_class.use(tar_io) { |reader| reader.extract_all(tmpdir) }

      expect(File.directory?(File.join(tmpdir, "subdir"))).to be true
      expect(File.read(File.join(tmpdir, "subdir", "file.txt"))).to eq("nested")
    end

    it "extracts symlinks" do
      io = StringIO.new.binmode
      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: "target.txt") { |s| s.write("content") }
        writer.add_symlink(name: "link.txt", target: "target.txt")
      end

      tar_io = StringIO.new(io.string).binmode
      described_class.use(tar_io) { |reader| reader.extract_all(tmpdir) }

      link_path = File.join(tmpdir, "link.txt")
      expect(File.symlink?(link_path)).to be true
      expect(File.readlink(link_path)).to eq("target.txt")
    end

    it "extracts hardlinks" do
      io = StringIO.new.binmode
      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: "original.txt") { |s| s.write("content") }
        writer.add_hardlink(name: "hardlink.txt", target: "original.txt")
      end

      tar_io = StringIO.new(io.string).binmode
      described_class.use(tar_io) { |reader| reader.extract_all(tmpdir) }

      original = File.join(tmpdir, "original.txt")
      hardlink = File.join(tmpdir, "hardlink.txt")
      expect(File.stat(original).ino).to eq(File.stat(hardlink).ino)
    end

    it "rejects path traversal in filenames" do
      io = StringIO.new.binmode
      # Manually craft a tar with path traversal - we can't use Writer's add_file
      # because it rejects traversal. Instead, use a real traversal attempt.
      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: "safe.txt") { |s| s.write("ok") }
      end

      # Create a tar with traversal by manipulating raw bytes
      tar_data = io.string.dup
      # Replace "safe.txt" with "../etc/passwd" padded to same length
      tar_data[0, 100] = "../escape.txt".ljust(100, "\0")
      # Recalculate checksum
      checksum_offset = 148
      tar_data[checksum_offset, 8] = " " * 8
      checksum = tar_data[0, 512].bytes.sum
      tar_data[checksum_offset, 8] = format("%06o\0 ", checksum)

      tar_io = StringIO.new(tar_data).binmode
      expect do
        described_class.use(tar_io) { |reader| reader.extract_all(tmpdir) }
      end.to raise_error(MiniTarball::PathTraversalError)
    end

    it "rejects absolute symlink targets" do
      io = StringIO.new.binmode
      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: "dummy.txt") { |s| s.write("x") }
      end

      # Manually create a symlink entry pointing to /etc/passwd
      tar_data = io.string.dup
      # Change typeflag to symlink (byte 156) and set linkname
      tar_data[156] = "2"
      tar_data[157, 100] = "/etc/passwd".ljust(100, "\0")
      # Recalculate checksum
      checksum_offset = 148
      tar_data[checksum_offset, 8] = " " * 8
      checksum = tar_data[0, 512].bytes.sum
      tar_data[checksum_offset, 8] = format("%06o\0 ", checksum)

      tar_io = StringIO.new(tar_data).binmode
      expect do
        described_class.use(tar_io) { |reader| reader.extract_all(tmpdir) }
      end.to raise_error(MiniTarball::PathTraversalError)
    end

    it "rejects symlinks escaping destination via .." do
      io = StringIO.new.binmode
      MiniTarball::Writer.use(io) do |writer|
        writer.add_symlink(name: "escape", target: "../../etc/passwd")
      end

      tar_io = StringIO.new(io.string).binmode
      expect do
        described_class.use(tar_io) { |reader| reader.extract_all(tmpdir) }
      end.to raise_error(MiniTarball::PathTraversalError)
    end

    it "returns self for chaining" do
      tar_io = create_tar
      reader = described_class.new(tar_io)

      result = reader.extract_all(tmpdir)

      expect(result).to be(reader)
    end
  end
end
