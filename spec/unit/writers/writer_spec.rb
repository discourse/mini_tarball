# frozen_string_literal: true

require "forwardable"
require "pathname"
require "tempfile"
require "time"
require "tmpdir"
require "zlib"

RSpec.describe MiniTarball::Writer do
  let(:io) { StringIO.new.binmode }

  let(:default_options) do
    {
      mode: 0644,
      mtime: Time.parse("2021-02-15T20:11:34Z"),
      uname: "discourse",
      gname: "www-data",
      uid: 1001,
      gid: 33,
    }
  end

  describe ".create" do
    it "creates a new tar file" do
      Tempfile.create do |temp_file|
        MiniTarball::Writer.create(temp_file.path) do |writer|
          %w[file1.txt file2.txt file3.txt].each do |filename|
            path = File.join(fixture_path("files"), filename)
            writer.file filename, content: File.binread(path), **default_options
          end
        end

        expect(temp_file.binmode.read).to eq(fixture("archives/multiple_files.tar"))
      end
    end
  end

  describe ".use" do
    it "closes the stream when it's done" do
      expect(io).to_not be_closed

      MiniTarball::Writer.use(io) do |writer|
        writer.file "test.txt", content: "hello", **default_options
      end

      expect(io).to be_closed
    end

    it "does not raise if the writer is closed inside the block" do
      expect do
        MiniTarball::Writer.use(io) do |writer|
          writer.file "test.txt", content: "hello", **default_options
          writer.close
        end
      end.not_to raise_error
    end
  end

  describe "#file" do
    describe "with from:" do
      let(:source_path) { fixture_path("files/file1.txt") }

      it "creates a valid tar with multiple files" do
        filenames = %w[file1.txt file2.txt file3.txt]

        MiniTarball::Writer.use(io) do |writer|
          filenames.each do |filename|
            path = File.join(fixture_path("files"), filename)
            writer.file filename, from: path, **default_options
          end
        end

        expect(io.string).to eq(fixture("archives/multiple_files.tar"))
      end

      it "accepts a Pathname" do
        MiniTarball::Writer.use(io) do |writer|
          writer.file "file1.txt", from: Pathname.new(source_path), **default_options
        end

        expected = StringIO.new.binmode
        MiniTarball::Writer.use(expected) do |writer|
          writer.file "file1.txt", from: source_path, **default_options
        end
        expect(io.string).to eq(expected.string)
      end

      it "rejects an Integer" do
        MiniTarball::Writer.use(io) do |writer|
          expect { writer.file "a.txt", from: 1 }.to raise_error(
            ArgumentError,
            "from: must be a String or respond to to_path",
          )
        end
      end

      it "works with a non-seekable IO object" do
        filenames = %w[file1.txt file2.txt file3.txt]
        gzip = Zlib::GzipWriter.new(io)

        MiniTarball::Writer.use(gzip) do |writer|
          filenames.each do |filename|
            path = File.join(fixture_path("files"), filename)
            writer.file filename, from: path, **default_options
          end
        end

        data = Zlib::GzipReader.new(StringIO.new(io.string, "rb")).read
        expect(data).to eq(fixture("archives/multiple_files.tar"))
      end

      it "rejects absolute paths" do
        MiniTarball::Writer.use(io) do |writer|
          expect { writer.file "/etc/passwd", from: source_path }.to raise_error(
            MiniTarball::UnsafeNameError,
            /Absolute paths are not allowed in name/,
          )
        end
      end

      it "matches GNU tar for unknown owner and group overrides" do
        allow(Etc).to receive(:getpwuid).with(123_456_789).and_raise(ArgumentError)
        allow(Etc).to receive(:getgrgid).with(123_456_788).and_raise(ArgumentError)

        Tempfile.create do |source|
          MiniTarball::Writer.use(io) do |writer|
            writer.file "empty.txt",
                        from: source.path,
                        **default_options.merge(
                          uid: 123_456_789,
                          gid: 123_456_788,
                          uname: nil,
                          gname: nil,
                        )
          end
        end

        expect(io.string[0, 512]).to eq(fixture("headers/numeric_owner_header"))
      end

      it "preserves source IDs when account lookup fails" do
        allow(Etc).to receive(:getpwuid).and_raise(ArgumentError)
        allow(Etc).to receive(:getgrgid).and_raise(ArgumentError)

        MiniTarball::Writer.use(io) { |writer| writer.file "test.txt", from: source_path }

        expect(io.string).to have_tar_header_field(:uname, "")
        expect(io.string).to have_tar_header_field(:gname, "")
        expect(io.string).to have_tar_header_field(:uid, format("%07o", File.stat(source_path).uid))
        expect(io.string).to have_tar_header_field(:gid, format("%07o", File.stat(source_path).gid))
      end
    end

    describe "with content:" do
      it "writes string content" do
        MiniTarball::Writer.use(io) do |writer|
          writer.file "test.txt", content: "hello world", **default_options
        end

        expect(io.string).to have_tar_header_field(:name, "test.txt")
        expect(io.string[512, 11]).to eq("hello world")
      end

      it "handles binary content with null bytes" do
        binary_content = "\x00\x01\x02\x03\x00\xFF\xFE\x00".b

        MiniTarball::Writer.use(io) do |writer|
          writer.file "binary.bin", content: binary_content, **default_options
        end

        file_content = io.string.b[512, binary_content.bytesize]
        expect(file_content).to eq(binary_content)
      end

      it "works with a non-seekable IO object" do
        gzip = Zlib::GzipWriter.new(io)
        content = "Hello, world!"

        MiniTarball::Writer.use(gzip) do |writer|
          writer.file "test.txt", content:, **default_options
        end

        data = Zlib::GzipReader.new(StringIO.new(io.string, "rb")).read
        expect(data).to have_tar_header_field(:name, "test.txt")
        expect(data[512, content.bytesize]).to eq(content)
      end

      it "uses default attributes when from: not provided" do
        MiniTarball::Writer.use(io) { |writer| writer.file "test.txt", content: "hello" }

        expect(io.string).to have_tar_header_field(:mode, "0000644")
        expect(io.string).to have_tar_header_field(:uname, "nobody")
        expect(io.string).to have_tar_header_field(:gname, "nogroup")
      end

      it "raises when size does not match content length" do
        MiniTarball::Writer.use(io) do |writer|
          expect { writer.file "test.txt", content: "hello", size: 100 }.to raise_error(
            ArgumentError,
            /Size 100 does not match content size 5/,
          )
        end
      end
    end

    describe "with from:" do
      it "raises when size does not match file size" do
        source_path = fixture_path("files/file1.txt")
        actual_size = File.size(source_path)

        MiniTarball::Writer.use(io) do |writer|
          expect {
            writer.file "test.txt", from: source_path, size: actual_size + 100
          }.to raise_error(ArgumentError, /does not match file size/)
        end
      end

      it "accepts matching size parameter" do
        source_path = fixture_path("files/file1.txt")
        actual_size = File.size(source_path)

        MiniTarball::Writer.use(io) do |writer|
          writer.file "test.txt", from: source_path, size: actual_size, **default_options
        end

        expected = StringIO.new.binmode
        MiniTarball::Writer.use(expected) do |writer|
          writer.file "test.txt", from: source_path, **default_options
        end
        expect(io.string).to eq(expected.string)
      end
    end

    describe "with block (streaming)" do
      it "creates a valid tar via streaming" do
        MiniTarball::Writer.use(io) do |writer|
          %w[file1.txt file2.txt file3.txt].each do |filename|
            path = File.join(fixture_path("files"), filename)
            writer.file(filename, **default_options) do |stream|
              File.open(path, "rb") { |f| IO.copy_stream(f, stream) }
            end
          end
        end

        expect(io.string).to eq(fixture("archives/multiple_files.tar"))
      end

      it "raises an error when a non-seekable IO is used without size:" do
        gzip = Zlib::GzipWriter.new(io)

        MiniTarball::Writer.use(gzip) do |writer|
          expect {
            writer.file("test.txt", **default_options) { |s| s.write("hello") }
          }.to raise_error(MiniTarball::NotSeekableError)
        end
      end

      it "works with gzip when size is provided" do
        gzip = Zlib::GzipWriter.new(io)
        content = "Hello, World!"

        MiniTarball::Writer.use(gzip) do |writer|
          writer.file("test.txt", size: content.bytesize, **default_options) do |s|
            s.write(content)
          end
        end

        data = Zlib::GzipReader.new(StringIO.new(io.string, "rb")).read
        expect(data).to have_tar_header_field(:name, "test.txt")
        expect(data).to have_tar_header_field(:size, content.bytesize)
      end

      it "raises an error when writing less than declared size" do
        MiniTarball::Writer.use(io) do |writer|
          expect {
            writer.file("test.txt", size: 100, **default_options) { |s| s.write("short") }
          }.to raise_error(MiniTarball::IncompleteWriteError, /declared 100 bytes but only 5/)
        end
      end

      it "keeps the archive block-aligned after an incomplete write" do
        MiniTarball::Writer.use(io) do |writer|
          expect {
            writer.file("test.txt", size: 100, **default_options) { |s| s.write("short") }
          }.to raise_error(MiniTarball::IncompleteWriteError)
        end

        expect(io.string.bytesize % 512).to eq(0)
      end

      it "pads with NUL bytes when writing less than declared size with allow_short_writes" do
        content = "short"
        declared_size = 100

        MiniTarball::Writer.use(io) do |writer|
          writer.file(
            "test.txt",
            size: declared_size,
            allow_short_writes: true,
            **default_options,
          ) { |s| s.write(content) }
        end

        file_content = io.string[512, declared_size]
        expect(file_content[0, content.length]).to eq(content)
        expect(file_content[content.length..]).to eq("\0" * (declared_size - content.length))
      end

      it "rejects allow_short_writes without a declared size" do
        MiniTarball::Writer.use(io) do |writer|
          expect {
            writer.file("test.txt", allow_short_writes: true, **default_options) do |s|
              s.write("x")
            end
          }.to raise_error(ArgumentError, /allow_short_writes requires size: and a block/)
        end
      end

      it "rejects allow_short_writes with content:" do
        MiniTarball::Writer.use(io) do |writer|
          expect {
            writer.file(
              "test.txt",
              content: "x",
              size: 1,
              allow_short_writes: true,
              **default_options,
            )
          }.to raise_error(ArgumentError, /allow_short_writes requires size: and a block/)
        end
      end

      it "raises error when writing more than declared size" do
        MiniTarball::Writer.use(io) do |writer|
          expect {
            writer.file("test.txt", size: 5, **default_options) { |s| s.write("too long!") }
          }.to raise_error(MiniTarball::WriteOutOfRangeError)
        end
      end

      it "rejects negative sizes" do
        MiniTarball::Writer.use(io) do |writer|
          expect {
            writer.file("test.txt", size: -1, **default_options) { |s| s.write("x") }
          }.to raise_error(ArgumentError, /non-negative/)
        end
      end
    end

    describe "source validation" do
      it "raises with helpful message when no source provided" do
        MiniTarball::Writer.use(io) do |writer|
          expect { writer.file("test.txt", **default_options) }.to raise_error(
            ArgumentError,
            /Provide exactly one of/,
          )
        end
      end

      it "raises with helpful message when multiple sources provided" do
        MiniTarball::Writer.use(io) do |writer|
          expect {
            writer.file("test.txt", content: "x", **default_options) { |s| s.write("y") }
          }.to raise_error(ArgumentError, /Provide exactly one of/)
        end
      end
    end

    describe "long names" do
      it "handles filename at exactly 100 bytes (no long link needed)" do
        name = "a" * 100

        MiniTarball::Writer.use(io) do |writer|
          writer.file name, content: "test", **default_options
        end

        expect(io.string).to have_tar_header_field(:name, name)
      end

      it "handles filename at 101 bytes (requires long link)" do
        name = "a" * 101

        MiniTarball::Writer.use(io) do |writer|
          writer.file name, content: "test", **default_options
        end

        expect(io.string).to have_tar_header_field(:name, "././@LongLink")
      end
    end
  end

  describe "#directory" do
    it "creates a directory entry" do
      MiniTarball::Writer.use(io) { |writer| writer.directory "mydir", **default_options }

      expect(io.string).to have_tar_header_field(:name, "mydir/")
      expect(io.string).to have_tar_header_field(:typeflag, "5")
    end

    it "uses defaults when attributes are explicitly nil" do
      MiniTarball::Writer.use(io) do |writer|
        writer.directory "mydir", mode: nil, uname: nil, gname: nil
      end

      expect(io.string).to have_tar_header_field(:mode, "0000755")
      expect(io.string).to have_tar_header_field(:uname, "nobody")
      expect(io.string).to have_tar_header_field(:gname, "nogroup")
    end

    it "preserves trailing slash if present" do
      MiniTarball::Writer.use(io) { |writer| writer.directory "mydir/", **default_options }

      expect(io.string).to have_tar_header_field(:name, "mydir/")
    end

    it "rejects path traversal" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.directory "../etc" }.to raise_error(MiniTarball::UnsafeNameError)
      end
    end
  end

  describe "#symlink" do
    it "uses defaults when attributes are explicitly nil" do
      MiniTarball::Writer.use(io) do |writer|
        writer.symlink "link", target: "file.txt", mode: nil, uname: nil, gname: nil
      end

      expect(io.string).to have_tar_header_field(:mode, "0000777")
      expect(io.string).to have_tar_header_field(:uname, "nobody")
      expect(io.string).to have_tar_header_field(:gname, "nogroup")
    end

    it "creates a symlink entry" do
      MiniTarball::Writer.use(io) do |writer|
        writer.symlink "link.txt", target: "target.txt", **default_options
      end

      expect(io.string).to have_tar_header_field(:name, "link.txt")
      expect(io.string).to have_tar_header_field(:typeflag, "2")
      expect(io.string).to have_tar_header_field(:linkname, "target.txt")
    end

    it "supports targets longer than 100 bytes" do
      long_target = "very/long/path/" + "a" * 100

      MiniTarball::Writer.use(io) do |writer|
        writer.file long_target, content: "content", **default_options
        writer.symlink "link.txt", target: long_target, **default_options
      end

      expect(io.string).to eq(fixture("archives/symlink_long_target.tar"))
    end

    it "stores targets of exactly 100 bytes in the header" do
      MiniTarball::Writer.use(io) { |writer| writer.symlink "link.txt", target: "a" * 100 }

      expect(io.string).to have_tar_header_field(:typeflag, "2")
      expect(io.string).to have_tar_header_field(:linkname, "a" * 100)
    end

    it "rejects path traversal in targets by default" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.symlink "subdir/link.txt", target: "../sibling/file.txt" }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Path traversal is not allowed in target/,
        )
      end
    end

    it "allows path traversal when explicitly permitted" do
      MiniTarball::Writer.use(io) do |writer|
        writer.symlink "subdir/link.txt",
                       target: "../sibling/file.txt",
                       allow_parent_references: true
      end

      expect(io.string).to have_tar_header_field(:linkname, "../sibling/file.txt")
    end
  end

  describe "#hardlink" do
    it "uses defaults when attributes are explicitly nil" do
      MiniTarball::Writer.use(io) do |writer|
        writer.hardlink "link", target: "file.txt", mode: nil, uname: nil, gname: nil
      end

      expect(io.string).to have_tar_header_field(:mode, "0000644")
      expect(io.string).to have_tar_header_field(:uname, "nobody")
      expect(io.string).to have_tar_header_field(:gname, "nogroup")
    end

    it "creates a hardlink entry" do
      MiniTarball::Writer.use(io) do |writer|
        writer.hardlink "link.txt", target: "target.txt", **default_options
      end

      expect(io.string).to have_tar_header_field(:name, "link.txt")
      expect(io.string).to have_tar_header_field(:typeflag, "1")
      expect(io.string).to have_tar_header_field(:linkname, "target.txt")
    end

    it "supports targets longer than 100 bytes" do
      long_target = "very/long/path/" + "a" * 100

      MiniTarball::Writer.use(io) do |writer|
        writer.file long_target, content: "content", **default_options
        writer.hardlink "link.txt", target: long_target, **default_options
      end

      expect(io.string).to eq(fixture("archives/hardlink_long_target.tar"))
    end

    it "rejects path traversal in targets by default" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.hardlink "link.txt", target: "../other/file.txt" }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Path traversal is not allowed in target/,
        )
      end
    end

    it "doesn't offer allow_parent_references, because targets are archive entry names" do
      MiniTarball::Writer.use(io) do |writer|
        expect {
          writer.hardlink "link.txt", target: "../other/file.txt", allow_parent_references: true
        }.to raise_error(ArgumentError, /unknown keyword: :allow_parent_references/)
      end
    end
  end

  describe "#placeholder" do
    it "rejects path traversal" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.placeholder "foo/../../passwd", size: 100 }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Path traversal is not allowed/,
        )
      end
    end

    it "rejects negative sizes" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.placeholder "file.txt", size: -1 }.to raise_error(
          ArgumentError,
          /non-negative/,
        )
      end
    end

    it "raises an error when a non-seekable IO object is used" do
      gzip = Zlib::GzipWriter.new(io)
      writer = described_class.new(gzip)

      expect { writer.placeholder "file1.txt", size: 100 }.to raise_error(
        MiniTarball::NotSeekableError,
      )
    end

    it "returns a Placeholder object" do
      writer = MiniTarball::Writer.new(io)
      placeholder = writer.placeholder "file.txt", size: 100

      expect(placeholder).to be_a(MiniTarball::Placeholder)
      expect(placeholder.name).to eq("file.txt")

      placeholder.fill content: "x"
      writer.close
    end

    it "allows filling placeholder at beginning of archive" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder =
          writer.placeholder "file1.txt", size: File.size(fixture_path("files/file1.txt"))

        %w[file2.txt file3.txt].each do |filename|
          path = File.join(fixture_path("files"), filename)
          writer.file filename, content: File.binread(path), **default_options
        end

        placeholder.fill from: fixture_path("files/file1.txt"), **default_options
      end

      expect(io.string).to eq(fixture("archives/multiple_files.tar"))
    end

    it "allows filling placeholders in any order" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder1 = writer.placeholder "file1.txt", size: 100
        placeholder2 = writer.placeholder "file2.txt", size: 100

        placeholder2.fill content: "content2", **default_options
        placeholder1.fill content: "content1", **default_options
      end

      expected = StringIO.new.binmode
      MiniTarball::Writer.use(expected) do |writer|
        %w[file1.txt content1 file2.txt content2].each_slice(2) do |name, content|
          writer.file(name, size: 100, allow_short_writes: true, **default_options) do |stream|
            stream.write(content)
          end
        end
      end

      expect(io.string).to eq(expected.string)
    end
  end

  describe "mixed entries" do
    it "creates an archive with files and links" do
      MiniTarball::Writer.use(io) do |writer|
        writer.file "file.txt", content: "content", **default_options
        writer.symlink "link.txt", target: "file.txt", **default_options
        writer.hardlink "hardlink.txt", target: "file.txt", **default_options
      end

      expect(io.string).to eq(fixture("archives/mixed_entries.tar"))
    end
  end

  describe "#close" do
    it "creates a valid tar file when manually closing the writer" do
      writer = MiniTarball::Writer.new(io)

      %w[file1.txt file2.txt file3.txt].each do |filename|
        path = File.join(fixture_path("files"), filename)
        writer.file filename, content: File.binread(path), **default_options
      end

      expect(writer.closed?).to eq(false)

      writer.close

      expect(writer.closed?).to eq(true)
      expect { writer.file "test.txt", content: "x" }.to raise_error(IOError)
      expect(io.string).to eq(fixture("archives/multiple_files.tar"))
    end

    it "is idempotent when closing an already-closed writer" do
      writer = MiniTarball::Writer.new(io)
      writer.close

      expect { writer.close }.not_to raise_error
      expect(writer.closed?).to be true
    end

    it "raises an error when placeholders are not filled and leaves the writer open" do
      writer = MiniTarball::Writer.new(io)
      writer.placeholder "file1.txt", size: 100

      expect { writer.close }.to raise_error(MiniTarball::UnfilledPlaceholderError)
      expect(writer.closed?).to eq(false)
      expect(io).not_to be_closed
    end

    it "can be closed after filling the placeholders that made close fail" do
      writer = MiniTarball::Writer.new(io)
      placeholder = writer.placeholder "file1.txt", size: 100

      expect { writer.close }.to raise_error(MiniTarball::UnfilledPlaceholderError)
      placeholder.fill content: "hello", **default_options
      writer.close

      expect(writer.closed?).to eq(true)
      expect(io.string.bytesize).to eq(512 + 512 + 1024)
      expect(io.string[-1024..]).to eq("\0" * 1024)
    end

    it "rejects filling a placeholder after Writer.use closed the IO" do
      placeholder = nil

      expect {
        MiniTarball::Writer.use(io) do |writer|
          placeholder = writer.placeholder "late.txt", size: 10
          raise "boom"
        end
      }.to raise_error(RuntimeError, "boom")

      expect(io).to be_closed
      expect { placeholder.fill content: "x" }.to raise_error(IOError, /Writer is closed/)
    end

    it "closes the IO in Writer.use when close fails because of unfilled placeholders" do
      expect {
        MiniTarball::Writer.use(io) { |writer| writer.placeholder "late.txt", size: 10 }
      }.to raise_error(MiniTarball::UnfilledPlaceholderError)

      expect(io).to be_closed
    end

    it "creates a valid empty archive with no entries" do
      MiniTarball::Writer.use(io) {}

      # Empty tar archives contain just the end-of-archive marker (1024 NUL bytes)
      expect(io.string.bytesize).to eq(1024)
      expect(io.string).to eq("\0" * 1024)
    end
  end

  it "raises an error when no valid IO object is used" do
    expect { MiniTarball::Writer.new(Object.new) }.to raise_error(MiniTarball::NoIOLikeObjectError)
  end

  describe "archive consistency after errors and out-of-order fills" do
    def build(&block)
      out = StringIO.new.binmode
      MiniTarball::Writer.use(out, &block)
      out.string
    end

    it "doesn't overwrite later entries when a filled placeholder is followed by another one" do
      expected =
        build do |w|
          w.file("a.txt", size: 512, allow_short_writes: true, **default_options) do |s|
            s.write("AAA")
          end
          w.file("b.txt", size: 512, allow_short_writes: true, **default_options) do |s|
            s.write("BBB")
          end
          w.file "c.txt", content: "CCC", **default_options
        end

      actual =
        build do |w|
          a = w.placeholder "a.txt", size: 512
          b = w.placeholder "b.txt", size: 512
          a.fill content: "AAA", **default_options
          w.file "c.txt", content: "CCC", **default_options
          b.fill content: "BBB", **default_options
        end

      expect(actual).to eq(expected)
    end

    it "doesn't leave a long name record behind when the main header fails" do
      expected = build { |w| w.file "ok.txt", content: "ok", **default_options }

      actual =
        build do |w|
          expect { w.file "n" * 150, content: "x", **default_options, uid: 2**56 }.to raise_error(
            MiniTarball::ValueTooLargeError,
          )
          w.file "ok.txt", content: "ok", **default_options
        end

      expect(actual).to eq(expected)
    end

    it "keeps writing at the end of the archive after a placeholder fill fails" do
      expected =
        build do |w|
          w.file "first.txt", content: "first", **default_options
          p = w.placeholder "p.txt", size: 10
          w.file "after.txt", content: "after", **default_options
          w.file "later.txt", content: "later", **default_options
          p.fill content: "x", **default_options
        end

      actual =
        build do |w|
          w.file "first.txt", content: "first", **default_options
          p = w.placeholder "p.txt", size: 10
          w.file "after.txt", content: "after", **default_options
          expect { p.fill content: "x", **default_options, uid: 2**60 }.to raise_error(
            MiniTarball::ValueTooLargeError,
          )
          w.file "later.txt", content: "later", **default_options
          p.fill content: "x", **default_options
        end

      expect(actual).to eq(expected)
    end

    it "rejects invalid attributes before streaming a file without size" do
      block_called = false

      actual =
        build do |w|
          expect {
            w.file("x.txt", **default_options, uid: 2**60) do |s|
              block_called = true
              s.write("data" * 300)
            end
          }.to raise_error(MiniTarball::ValueTooLargeError)
          w.file "later.txt", content: "later", **default_options
        end

      expect(block_called).to be(false)
      expect(actual).to eq(build { |w| w.file "later.txt", content: "later", **default_options })
    end

    it "uses the validated placeholder name even if the caller mutates its string later" do
      expected =
        build do |w|
          w.file("safe.txt", size: 10, allow_short_writes: true, **default_options) do |s|
            s.write("x")
          end
        end

      placeholder = nil
      actual =
        build do |w|
          name = +"safe.txt"
          placeholder = w.placeholder name, size: 10
          name.replace("../#{"a" * 120}")
          placeholder.fill content: "x", **default_options
        end

      expect(actual).to eq(expected)
      expect(placeholder.name).to eq("safe.txt")
      expect(placeholder.name).to be_frozen
    end

    it "uses the validated name of a streamed file even if the block mutates its string" do
      expected = build { |w| w.file("safe.txt", **default_options) { |s| s.write("data") } }

      actual =
        build do |w|
          name = +"safe.txt"
          w.file(name, **default_options) do |s|
            s.write("data")
            name.replace("../#{"a" * 120}")
          end
        end

      expect(actual).to eq(expected)
    end

    it "rejects a placeholder fill from a file larger than the reservation before writing" do
      Tempfile.create do |source|
        source.write("x" * 100)
        source.flush

        actual =
          build do |w|
            p = w.placeholder "p.txt", size: 10
            expect { p.fill from: source.path, **default_options }.to raise_error(
              MiniTarball::WriteOutOfRangeError,
            )
            p.fill content: "ok", **default_options
          end

        expected =
          build do |w|
            w.file("p.txt", size: 10, allow_short_writes: true, **default_options) do |s|
              s.write("ok")
            end
          end
        expect(actual).to eq(expected)
      end
    end

    it "rejects from: a directory before writing anything" do
      Dir.mktmpdir do |dir|
        actual =
          build do |w|
            expect { w.file "d", from: dir }.to raise_error(ArgumentError, /regular file/)
          end

        expect(actual).to eq("\0" * 1024)
      end
    end

    it "keeps an Interrupt from the block when closing fails afterwards" do
      expect {
        MiniTarball::Writer.use(io) do |writer|
          writer.placeholder "p.txt", size: 1
          raise Interrupt
        end
      }.to raise_error(Interrupt)
    end

    it "marks the writer closed even when closing the IO raises" do
      failing_io = StringIO.new.binmode
      def failing_io.close
        raise Errno::ENOSPC
      end

      writer = MiniTarball::Writer.new(failing_io)

      expect { writer.close }.to raise_error(Errno::ENOSPC)
      expect(writer.closed?).to be(true)
      expect { writer.close }.not_to raise_error
    end

    it "converts non-String writes the same way with and without size" do
      sized = build { |w| w.file("i", size: 2, **default_options) { |s| s.write(42) } }
      seekable = build { |w| w.file("i", **default_options) { |s| s.write(42) } }

      expect(sized[512, 2]).to eq("42")
      expect(sized).to eq(seekable)
    end
  end

  describe "input validation" do
    it "only lets directories end with a slash" do
      MiniTarball::Writer.use(io) do |w|
        expect { w.file "foo/", content: "x" }.to raise_error(
          MiniTarball::UnsafeNameError,
          /may end with/,
        )
        expect { w.placeholder "foo/", size: 1 }.to raise_error(MiniTarball::UnsafeNameError)
        expect { w.symlink "foo/", target: "bar" }.to raise_error(MiniTarball::UnsafeNameError)
        expect { w.hardlink "foo/", target: "bar" }.to raise_error(MiniTarball::UnsafeNameError)
        expect { w.directory "foo/" }.not_to raise_error
      end
    end

    it "rejects owner names that don't fit the header field" do
      MiniTarball::Writer.use(io) do |w|
        expect { w.file "a", content: "x", uname: "a" * 33 }.to raise_error(ArgumentError, /uname/)
        expect { w.directory "d", gname: "g" * 33 }.to raise_error(ArgumentError, /gname/)
      end
    end

    it "rejects owner names with control characters" do
      MiniTarball::Writer.use(io) do |w|
        expect { w.file "a", content: "x", uname: "a\nb" }.to raise_error(ArgumentError, /uname/)
        expect { w.file "a", content: "x", gname: "a\0b" }.to raise_error(ArgumentError, /gname/)
      end
    end

    it "accepts owner names of exactly 32 bytes" do
      MiniTarball::Writer.use(io) { |w| w.file "a", content: "x", uname: "u" * 32, gname: "g" * 32 }

      expect(io.string).to have_tar_header_field(:uname, "u" * 32)
      expect(io.string).to have_tar_header_field(:gname, "g" * 32)
    end

    it "raises ArgumentError for names that aren't Strings" do
      MiniTarball::Writer.use(io) do |w|
        expect { w.file :sym, content: "x" }.to raise_error(ArgumentError, /name must be a String/)
        expect { w.directory 123 }.to raise_error(ArgumentError, /name must be a String/)
      end
    end

    it "raises ArgumentError for sizes that aren't Integers" do
      MiniTarball::Writer.use(io) do |w|
        expect { w.file("f", size: 10.5) { |s| s.write("x") } }.to raise_error(
          ArgumentError,
          /Size must be an Integer/,
        )
        expect { w.placeholder "p", size: "10" }.to raise_error(
          ArgumentError,
          /Size must be an Integer/,
        )
      end
    end

    it "raises NotSeekableError for pipes that respond to seek but can't seek" do
      reader, pipe = IO.pipe
      writer = MiniTarball::Writer.new(pipe)

      expect { writer.placeholder "p", size: 10 }.to raise_error(MiniTarball::NotSeekableError)
      expect { writer.file("s") { |s| s.write("x") } }.to raise_error(MiniTarball::NotSeekableError)
    ensure
      reader&.close
      pipe&.close
    end
  end

  describe "error messages" do
    it "explains an invalid IO" do
      expect { MiniTarball::Writer.new(Object.new) }.to raise_error(
        MiniTarball::NoIOLikeObjectError,
        "IO object is not valid",
      )
    end

    it "explains a missing seek" do
      writer = MiniTarball::Writer.new(Zlib::GzipWriter.new(StringIO.new))

      expect { writer.placeholder "p", size: 1 }.to raise_error(
        MiniTarball::NotSeekableError,
        "IO object is not seekable",
      )
    end

    it "explains unfilled placeholders" do
      writer = MiniTarball::Writer.new(io)
      writer.placeholder "p", size: 1

      expect { writer.close }.to raise_error(
        MiniTarball::UnfilledPlaceholderError,
        "Unfilled placeholders remain",
      )
    end

    it "names the type of an invalid size" do
      MiniTarball::Writer.use(io) do |w|
        expect { w.file("f", size: 1.5) { nil } }.to raise_error(
          ArgumentError,
          "Size must be an Integer, got Float",
        )
      end
    end

    it "names a file name that ends with a slash" do
      MiniTarball::Writer.use(io) do |w|
        expect { w.file "foo/", content: "x" }.to raise_error(
          MiniTarball::UnsafeNameError,
          "Only directory names may end with '/': foo/",
        )
      end
    end
  end

  it "keeps custom messages on its error classes" do
    [
      MiniTarball::NoIOLikeObjectError,
      MiniTarball::NotSeekableError,
      MiniTarball::UnfilledPlaceholderError,
    ].each { |error_class| expect(error_class.new("custom").message).to eq("custom") }
  end

  describe "IO requirements" do
    %i[pos write close].each do |missing|
      it "rejects an IO without ##{missing}" do
        io_like = StringIO.new
        io_like.singleton_class.undef_method(missing)

        expect { MiniTarball::Writer.new(io_like) }.to raise_error(MiniTarball::NoIOLikeObjectError)
      end
    end

    it "writes after content that is already in the IO" do
      prefixed = StringIO.new(+"prefix")
      prefixed.seek(0, IO::SEEK_END)

      MiniTarball::Writer.use(prefixed) do |w|
        w.file("a.txt", **default_options) { |s| s.write("x") }
      end

      expect(prefixed.string).to start_with("prefix")
      expect(prefixed.string.byteslice(6, 5)).to eq("a.txt")
    end

    it "doesn't let a streaming block seek in the archive" do
      MiniTarball::Writer.use(io) do |w|
        w.file("a.txt", **default_options) { |stream| expect(stream).not_to respond_to(:seek) }
      end
    end
  end

  describe "IO that can't rewrite headers" do
    let(:append_message) { "IO is in append mode, headers can't be rewritten" }
    let(:seek_message) do
      "IO did not seek to the header, so it can't be rewritten (expected position 512, got 1536)"
    end

    def build(&block)
      out = StringIO.new.binmode
      MiniTarball::Writer.use(out, &block)
      out.string
    end

    def write_to_append_file
      Dir.mktmpdir do |dir|
        path = File.join(dir, "archive.tar")
        File.open(path, "ab") do |file|
          writer = MiniTarball::Writer.new(file)
          writer.file "a.txt", content: "a", **default_options
          yield writer
          writer.close
        end
        File.binread(path)
      end
    end

    let(:archive_with_first_entry) { build { |w| w.file "a.txt", content: "a", **default_options } }

    it "rejects streaming without size: to a file in append mode before writing the entry" do
      archive =
        write_to_append_file do |writer|
          expect { writer.file("b.txt") { |s| s.write("hello") } }.to raise_error(
            MiniTarball::NotSeekableError,
            append_message,
          )
        end

      expect(archive).to eq(archive_with_first_entry)
    end

    it "rejects placeholders in a file in append mode before writing the entry" do
      archive =
        write_to_append_file do |writer|
          expect { writer.placeholder("b.txt", size: 10) }.to raise_error(
            MiniTarball::NotSeekableError,
            append_message,
          )
        end

      expect(archive).to eq(archive_with_first_entry)
    end

    it "accepts streaming with size: to a file in append mode" do
      archive = write_to_append_file { |writer| writer.file("b.txt", size: 1) { |s| s.write("b") } }

      expected =
        build do |w|
          w.file "a.txt", content: "a", **default_options
          w.file("b.txt", size: 1) { |s| s.write("b") }
        end
      expect(archive.bytesize).to eq(expected.bytesize)
      expect(archive[0, 1024]).to eq(expected[0, 1024])
    end

    it "streams to a file that isn't in append mode" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "archive.tar")
        File.open(path, "wb") do |file|
          MiniTarball::Writer.use(file) do |w|
            w.file("a.txt", **default_options) { |s| s.write("a") }
          end
        end

        expect(File.binread(path)).to eq(archive_with_first_entry)
      end
    end

    [Errno::EINVAL, NotImplementedError, ArgumentError].each do |error_class|
      it "treats an IO as not in append mode when fcntl raises #{error_class}" do
        out = StringIO.new.binmode
        out.define_singleton_method(:fcntl) { |*| raise error_class }

        MiniTarball::Writer.use(out) { |w| w.file("a.txt", **default_options) { |s| s.write("a") } }

        expect(out.string).to eq(archive_with_first_entry)
      end
    end

    def stuck_seek_writer
      out = StringIO.new.binmode
      out.define_singleton_method(:seek) { |*| 0 }
      MiniTarball::Writer.new(out)
    end

    it "raises when streaming without size: and the IO doesn't seek to the header" do
      writer = stuck_seek_writer

      expect { writer.file("a.txt") { |s| s.write("a") } }.to raise_error(
        MiniTarball::NotSeekableError,
        seek_message,
      )
    end

    it "raises when filling a placeholder and the IO doesn't seek to the header" do
      writer = stuck_seek_writer
      placeholder = writer.placeholder("a.txt", size: 10)

      expect { placeholder.fill(content: "a") }.to raise_error(
        MiniTarball::NotSeekableError,
        seek_message,
      )
    end
  end

  describe "IO wrappers with different return values" do
    def wrapped_io(write_result: :count, seek_result: :position)
      Class
        .new do
          extend Forwardable
          def_delegators :@io, :pos, :close, :closed?, :string

          def initialize(write_result, seek_result)
            @io = StringIO.new.binmode
            @write_result = write_result
            @seek_result = seek_result
          end

          def write(data)
            count = @io.write(data)
            case @write_result
            when :count
              count
            when :self
              self
            end
          end

          def seek(*args)
            position = @io.seek(*args)
            @seek_result == :position ? position : @seek_result
          end
        end
        .new(write_result, seek_result)
    end

    def write_all_entry_kinds(writer)
      placeholder = writer.placeholder("p.txt", size: 10)
      writer.file("streamed.txt", **default_options) { |s| s.write("streamed") }
      writer.file("sized.txt", size: 5, **default_options) { |s| s.write("sized") }
      writer.file("#{"long" * 30}.txt", content: "long name", **default_options)
      writer.file("from.txt", from: fixture_path("files/file1.txt"), **default_options)
      writer.directory("d", **default_options)
      placeholder.fill(content: "filled", **default_options)
    end

    let(:expected) do
      StringIO.new.binmode.tap { |out| write_all_entry_kinds(described_class.new(out)) }
    end

    it "uses placeholders and streaming without size when seek returns nil" do
      wrapper = wrapped_io(seek_result: nil)

      write_all_entry_kinds(described_class.new(wrapper))

      expect(wrapper.string).to eq(expected.string)
    end

    %i[nil self].each do |write_result|
      it "writes the same bytes when write returns #{write_result}" do
        wrapper = wrapped_io(write_result:)

        write_all_entry_kinds(described_class.new(wrapper))

        expect(wrapper.string).to eq(expected.string)
      end
    end
  end

  describe "nested entries" do
    let(:message) { "Another entry is still being written" }

    def build(&block)
      out = StringIO.new.binmode
      MiniTarball::Writer.use(out, &block)
      out.string
    end

    def write_outer(writer, kind, &inner)
      write_and_call =
        lambda do |stream|
          stream.write("x")
          inner.call
        end

      case kind
      when :streaming
        writer.file("a.txt", **default_options, &write_and_call)
      when :sized
        writer.file("a.txt", size: 1, **default_options, &write_and_call)
      when :fill
        writer.placeholder("a.txt", size: 1024).fill(**default_options, &write_and_call)
      end
    end

    # Each archive starts with a placeholder, so the nested call can try to fill it.
    def build_with(kind, &inner)
      build do |w|
        placeholder = w.placeholder("p.txt", size: 10)
        write_outer(w, kind) { inner.call(w, placeholder) }
        w.file "later.txt", content: "later", **default_options
        placeholder.fill content: "p", **default_options
      end
    end

    nested_calls = {
      file: ->(w, _) { w.file "b.txt", content: "hello" },
      file_with_block: ->(w, _) { w.file("b.txt") { |s| s.write("hello") } },
      directory: ->(w, _) { w.directory "d" },
      symlink: ->(w, _) { w.symlink "l", target: "a.txt" },
      hardlink: ->(w, _) { w.hardlink "h", target: "a.txt" },
      placeholder: ->(w, _) { w.placeholder "q.txt", size: 1 },
      fill: ->(_, placeholder) { placeholder.fill content: "p" },
      close: ->(w, _) { w.close },
    }

    %i[streaming sized fill].each do |kind|
      nested_calls.each do |method, call|
        it "rejects ##{method} inside a #{kind} block and keeps the archive valid" do
          expected = build_with(kind) { nil }

          actual =
            build_with(kind) do |w, placeholder|
              expect { call.call(w, placeholder) }.to raise_error(IOError, message)
            end

          expect(actual).to eq(expected)
        end
      end
    end

    it "keeps rejecting nested calls after one was rejected" do
      MiniTarball::Writer.use(io) do |w|
        placeholder = w.placeholder("p.txt", size: 1)
        w.file("a.txt") do
          expect { placeholder.fill content: "p" }.to raise_error(IOError, message)
          expect { w.file "b.txt", content: "b" }.to raise_error(IOError, message)
        end
        placeholder.fill content: "p"
      end
    end

    it "accepts new entries after a streaming block raised" do
      expected =
        build do |w|
          w.file("a.txt", size: 1, allow_short_writes: true, **default_options) { nil }
          w.file "b.txt", content: "b", **default_options
        end

      actual =
        build do |w|
          expect { w.file("a.txt", size: 1, **default_options) { raise "boom" } }.to raise_error(
            "boom",
          )
          w.file "b.txt", content: "b", **default_options
        end

      expect(actual).to eq(expected)
    end

    it "accepts new entries after a fill block raised" do
      expected =
        build do |w|
          w.placeholder("p.txt", size: 1).fill(content: "p", **default_options)
          w.file "b.txt", content: "b", **default_options
        end

      actual =
        build do |w|
          placeholder = w.placeholder("p.txt", size: 1)
          expect { placeholder.fill { raise "boom" } }.to raise_error("boom")
          w.file "b.txt", content: "b", **default_options
          placeholder.fill content: "p", **default_options
        end

      expect(actual).to eq(expected)
    end
  end

  describe "after close" do
    let(:writer) { MiniTarball::Writer.new(io).tap(&:close) }

    {
      file: ->(w) { w.file "a", content: "x" },
      directory: ->(w) { w.directory "d" },
      symlink: ->(w) { w.symlink "l", target: "a" },
      hardlink: ->(w) { w.hardlink "h", target: "a" },
      placeholder: ->(w) { w.placeholder "p", size: 1 },
    }.each do |method, call|
      it "raises from ##{method}" do
        expect { call.call(writer) }.to raise_error(IOError, "MiniTarball::Writer is closed")
      end
    end

    {
      file: ->(w) { w.file "/a", content: "x" },
      directory: ->(w) { w.directory "/d" },
      symlink: ->(w) { w.symlink "/l", target: "a" },
      hardlink: ->(w) { w.hardlink "/h", target: "a" },
      placeholder: ->(w) { w.placeholder "/p", size: 1 },
    }.each do |method, call|
      it "raises from ##{method} before checking the name" do
        expect { call.call(writer) }.to raise_error(IOError, "MiniTarball::Writer is closed")
      end
    end

    {
      symlink: ->(w) { w.symlink "l", target: "a", mode: -1 },
      hardlink: ->(w) { w.hardlink "h", target: "a", mode: -1 },
    }.each do |method, call|
      it "raises from ##{method} before checking the attributes" do
        expect { call.call(writer) }.to raise_error(IOError, "MiniTarball::Writer is closed")
      end
    end
  end

  describe "entry details" do
    it "returns the writer from every entry method" do
      MiniTarball::Writer.use(io) do |w|
        expect(w.file("a", content: "x")).to be(w)
        expect(w.directory("d")).to be(w)
        expect(w.symlink("l", target: "a")).to be(w)
        expect(w.hardlink("h", target: "a")).to be(w)
      end
    end

    it "writes all attributes of a directory" do
      MiniTarball::Writer.use(io) { |w| w.directory "d", **default_options }

      expect(io.string).to have_tar_header_field(:size, 0)
      expect(io.string).to have_tar_header_field(:uid, 1001)
      expect(io.string).to have_tar_header_field(:gid, 33)
      expect(io.string).to have_tar_header_field(:uname, "discourse")
      expect(io.string).to have_tar_header_field(:gname, "www-data")
      expect(io.string).to have_tar_header_field(:mtime, default_options[:mtime].to_i)
    end

    it "uses the given mode for a hardlink" do
      MiniTarball::Writer.use(io) { |w| w.hardlink "h", target: "a", mode: 0o600 }

      expect(io.string).to have_tar_header_field(:mode, "0000600")
    end

    it "accepts a size of 0" do
      MiniTarball::Writer.use(io) do |w|
        w.file("empty", size: 0, **default_options) { nil }
        w.placeholder("reserved", size: 0).fill(content: "", **default_options)
      end

      expect(io.string).to have_tar_header_field(:size, 0)
    end

    it "creates a file whose name starts with a pipe instead of running a command" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          MiniTarball::Writer.create("|touch ran") { |w| w.file "a", content: "x" }

          expect(File.exist?("|touch ran")).to be(true)
          expect(File.exist?("ran")).to be(false)
        end
      end
    end
  end
end
