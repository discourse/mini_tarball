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

    context "with malicious long name/linkname entries" do
      def create_long_name_header(size:, typeflag:)
        # Create a valid GNU long name/linkname header
        header =
          MiniTarball::Header.new(
            name: "././@LongLink",
            mode: 0644,
            uid: 0,
            gid: 0,
            size:,
            typeflag:,
            uname: "root",
            gname: "root",
          )
        header.to_binary
      end

      it "raises error for oversized long name entry" do
        # Create a tar with a long name entry claiming 100KB size
        header = create_long_name_header(size: 100_000, typeflag: "L")
        # Append minimal content and padding (doesn't matter, error raised before reading)
        tar_data = header + ("x" * 512) + ("\0" * 1024)

        tar_io = StringIO.new(tar_data).binmode
        expect do described_class.use(tar_io) { |reader| reader.each_entry {} } end.to raise_error(
          MiniTarball::InvalidHeaderError,
          "Long name too large",
        )
      end

      it "raises error for oversized long linkname entry" do
        header = create_long_name_header(size: 100_000, typeflag: "K")
        tar_data = header + ("x" * 512) + ("\0" * 1024)

        tar_io = StringIO.new(tar_data).binmode
        expect do described_class.use(tar_io) { |reader| reader.each_entry {} } end.to raise_error(
          MiniTarball::InvalidHeaderError,
          "Long linkname too large",
        )
      end

      it "accepts long name entries within size limit" do
        # 65535 bytes is at the limit
        io = StringIO.new.binmode
        long_name = "a" * 65_000 + ".txt"
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
    end

    context "with chunked skipping" do
      it "correctly skips large unread content between entries" do
        io = StringIO.new.binmode
        # Create a file with content larger than skip chunk size (64KB)
        large_content = "x" * 100_000
        MiniTarball::Writer.use(io) do |writer|
          writer.add_file_from_stream(name: "large.txt") { |s| s.write(large_content) }
          writer.add_file_from_stream(name: "small.txt") { |s| s.write("small") }
        end

        tar_io = StringIO.new(io.string).binmode
        entries = []
        contents = {}

        described_class.use(tar_io) do |reader|
          reader.each_entry do |entry, stream|
            entries << entry.name
            # Only read the second file's content, skip the first
            contents[entry.name] = stream.read if entry.name == "small.txt"
          end
        end

        expect(entries).to eq(%w[large.txt small.txt])
        expect(contents["small.txt"]).to eq("small")
      end
    end

    context "with max_file_size validation" do
      def create_file_header(size:)
        MiniTarball::Header.new(
          name: "large.txt",
          mode: 0644,
          uid: 0,
          gid: 0,
          size:,
          uname: "root",
          gname: "root",
        )
      end

      it "raises error for file exceeding max_file_size" do
        # Create a header claiming 10GB size
        header = create_file_header(size: 10_000_000_000)
        tar_data = header.to_binary + ("\0" * 1024)

        tar_io = StringIO.new(tar_data).binmode
        expect do described_class.use(tar_io) { |reader| reader.each_entry {} } end.to raise_error(
          MiniTarball::InvalidHeaderError,
          /File size exceeds maximum/,
        )
      end

      it "allows custom max_file_size" do
        # Create a header claiming 1KB size
        header = create_file_header(size: 1024)
        content = "x" * 1024
        padding = "\0" * (512 - (1024 % 512))
        tar_data = header.to_binary + content + padding + ("\0" * 1024)

        tar_io = StringIO.new(tar_data).binmode
        # Set max to 500 bytes - should reject 1KB file
        expect do
          described_class.use(tar_io, max_file_size: 500) { |reader| reader.each_entry {} }
        end.to raise_error(MiniTarball::InvalidHeaderError, /File size exceeds maximum/)
      end

      it "accepts file at exactly max_file_size" do
        io = StringIO.new.binmode
        content = "x" * 100
        MiniTarball::Writer.use(io) do |writer|
          writer.add_file_from_stream(name: "exact.txt") { |s| s.write(content) }
        end

        tar_io = StringIO.new(io.string).binmode
        entries = []
        described_class.use(tar_io, max_file_size: 100) do |reader|
          reader.each_entry { |entry, _| entries << entry.name }
        end

        expect(entries).to eq(["exact.txt"])
      end

      it "uses default 8GB limit" do
        io = StringIO.new.binmode
        MiniTarball::Writer.use(io) do |writer|
          writer.add_file_from_stream(name: "normal.txt") { |s| s.write("content") }
        end

        tar_io = StringIO.new(io.string).binmode
        entries = []
        # Default should allow normal files
        described_class.use(tar_io) do |reader|
          reader.each_entry { |entry, _| entries << entry.name }
        end

        expect(entries).to eq(["normal.txt"])
      end
    end

    context "with max_total_size validation" do
      it "raises error when total size exceeds limit" do
        io = StringIO.new.binmode
        MiniTarball::Writer.use(io) do |writer|
          writer.add_file_from_stream(name: "file1.txt") { |s| s.write("a" * 100) }
          writer.add_file_from_stream(name: "file2.txt") { |s| s.write("b" * 100) }
          writer.add_file_from_stream(name: "file3.txt") { |s| s.write("c" * 100) }
        end

        tar_io = StringIO.new(io.string).binmode
        # Total is 300 bytes, limit to 250
        expect do
          described_class.use(tar_io, max_total_size: 250) { |reader| reader.each_entry {} }
        end.to raise_error(MiniTarball::ArchiveLimitError, /Total size exceeds maximum/)
      end

      it "allows archives within total size limit" do
        io = StringIO.new.binmode
        MiniTarball::Writer.use(io) do |writer|
          writer.add_file_from_stream(name: "file1.txt") { |s| s.write("a" * 100) }
          writer.add_file_from_stream(name: "file2.txt") { |s| s.write("b" * 100) }
        end

        tar_io = StringIO.new(io.string).binmode
        entries = []
        described_class.use(tar_io, max_total_size: 200) do |reader|
          reader.each_entry { |entry, _| entries << entry.name }
        end

        expect(entries).to eq(%w[file1.txt file2.txt])
      end
    end

    context "with max_entry_count validation" do
      it "raises error when entry count exceeds limit" do
        io = StringIO.new.binmode
        MiniTarball::Writer.use(io) do |writer|
          5.times { |i| writer.add_file_from_stream(name: "file#{i}.txt") { |s| s.write("x") } }
        end

        tar_io = StringIO.new(io.string).binmode
        expect do
          described_class.use(tar_io, max_entry_count: 3) { |reader| reader.each_entry {} }
        end.to raise_error(MiniTarball::ArchiveLimitError, /Entry count exceeds maximum/)
      end

      it "allows archives within entry count limit" do
        io = StringIO.new.binmode
        MiniTarball::Writer.use(io) do |writer|
          3.times { |i| writer.add_file_from_stream(name: "file#{i}.txt") { |s| s.write("x") } }
        end

        tar_io = StringIO.new(io.string).binmode
        entries = []
        described_class.use(tar_io, max_entry_count: 3) do |reader|
          reader.each_entry { |entry, _| entries << entry.name }
        end

        expect(entries).to eq(%w[file0.txt file1.txt file2.txt])
      end

      it "does not count long name entries toward limit" do
        io = StringIO.new.binmode
        long_name = "a" * 150 + ".txt"
        MiniTarball::Writer.use(io) do |writer|
          writer.add_file_from_stream(name: long_name) { |s| s.write("content") }
          writer.add_file_from_stream(name: "short.txt") { |s| s.write("content") }
        end

        tar_io = StringIO.new(io.string).binmode
        entries = []
        # Long name uses internal ././@LongLink entry, but should only count as 1 user entry
        described_class.use(tar_io, max_entry_count: 2) do |reader|
          reader.each_entry { |entry, _| entries << entry.name }
        end

        expect(entries).to eq([long_name, "short.txt"])
      end
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

    context "with symlink-in-path attacks" do
      it "rejects extraction through pre-existing symlink pointing outside destination" do
        # Create a symlink inside tmpdir pointing to /tmp (outside destination)
        outside_dir = Dir.mktmpdir
        begin
          symlink_path = File.join(tmpdir, "escape_link")
          File.symlink(outside_dir, symlink_path)

          # Create a tar that writes through the symlink
          io = StringIO.new.binmode
          MiniTarball::Writer.use(io) do |writer|
            writer.add_file_from_stream(name: "escape_link/pwned.txt") { |s| s.write("pwned") }
          end

          tar_io = StringIO.new(io.string).binmode
          expect do
            described_class.use(tar_io) { |reader| reader.extract_all(tmpdir) }
          end.to raise_error(MiniTarball::PathTraversalError, /Symlink in path escapes destination/)
        ensure
          FileUtils.rm_rf(outside_dir)
        end
      end

      it "allows extraction through symlink pointing within destination" do
        # Create a subdirectory and symlink to it within tmpdir
        real_dir = File.join(tmpdir, "real_subdir")
        FileUtils.mkdir_p(real_dir)
        symlink_path = File.join(tmpdir, "link_to_subdir")
        File.symlink(real_dir, symlink_path)

        io = StringIO.new.binmode
        MiniTarball::Writer.use(io) do |writer|
          writer.add_file_from_stream(name: "link_to_subdir/file.txt") { |s| s.write("content") }
        end

        tar_io = StringIO.new(io.string).binmode
        described_class.use(tar_io) { |reader| reader.extract_all(tmpdir) }

        expect(File.read(File.join(real_dir, "file.txt"))).to eq("content")
      end

      it "handles deeply nested paths correctly" do
        io = StringIO.new.binmode
        MiniTarball::Writer.use(io) do |writer|
          writer.add_directory(name: "a/b/c/d")
          writer.add_file_from_stream(name: "a/b/c/d/deep.txt") { |s| s.write("deep") }
        end

        tar_io = StringIO.new(io.string).binmode
        described_class.use(tar_io) { |reader| reader.extract_all(tmpdir) }

        expect(File.read(File.join(tmpdir, "a/b/c/d/deep.txt"))).to eq("deep")
      end
    end

    it "returns self for chaining" do
      tar_io = create_tar
      reader = described_class.new(tar_io)

      result = reader.extract_all(tmpdir)

      expect(result).to be(reader)
    end
  end
end
