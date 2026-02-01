# frozen_string_literal: true

require "tempfile"
require "time"
require "zlib"
require_relative "../integration/support/gnu_tar"

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

  def with_temp_tar(filenames, fixture_directory: "files")
    skip(GnuTar.skip_message) unless GnuTar.available?

    Dir.mktmpdir do |temp_dir|
      output_filename = File.join(temp_dir, "test.tar")

      GnuTar.create(
        output_filename,
        files: filenames,
        chdir: fixture_path(fixture_directory),
        blocking_factor: 1,
      )

      yield(File.binread(output_filename))
    end
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

    it "preserves the original error when close fails" do
      expect {
        MiniTarball::Writer.use(io) do |writer|
          writer.placeholder "test.txt", size: 10
          raise "boom"
        end
      }.to raise_error(RuntimeError, "boom")
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
            writer.file filename, from: path
          end
        end

        with_temp_tar(filenames) { |tar| expect(io.string).to eq(tar) }
      end

      it "works with a non-seekable IO object" do
        filenames = %w[file1.txt file2.txt file3.txt]
        gzip = Zlib::GzipWriter.new(io)

        MiniTarball::Writer.use(gzip) do |writer|
          filenames.each do |filename|
            path = File.join(fixture_path("files"), filename)
            writer.file filename, from: path
          end
        end

        data = Zlib::GzipReader.new(StringIO.new(io.string, "rb")).read
        with_temp_tar(filenames) { |tar| expect(data).to eq(tar) }
      end

      it "rejects absolute paths" do
        MiniTarball::Writer.use(io) do |writer|
          expect { writer.file "/etc/passwd", from: source_path }.to raise_error(
            MiniTarball::UnsafeNameError,
            /Absolute paths are not allowed/,
          )
        end
      end

      it "rejects path traversal" do
        MiniTarball::Writer.use(io) do |writer|
          expect { writer.file "../etc/passwd", from: source_path }.to raise_error(
            MiniTarball::UnsafeNameError,
            /Path traversal is not allowed/,
          )

          expect { writer.file "foo/../../../etc/passwd", from: source_path }.to raise_error(
            MiniTarball::UnsafeNameError,
            /Path traversal is not allowed/,
          )
        end
      end

      it "rejects empty name" do
        MiniTarball::Writer.use(io) do |writer|
          expect { writer.file "", from: source_path }.to raise_error(
            MiniTarball::UnsafeNameError,
            /Empty name not allowed/,
          )
        end
      end

      it "allows relative paths without traversal" do
        MiniTarball::Writer.use(io) do |writer|
          expect { writer.file "subdir/file.txt", from: source_path }.not_to raise_error
        end
      end

      it "handles missing UID/GID gracefully" do
        allow(Etc).to receive(:getpwuid).and_raise(ArgumentError)
        allow(Etc).to receive(:getgrgid).and_raise(ArgumentError)

        MiniTarball::Writer.use(io) { |writer| writer.file "test.txt", from: source_path }

        expect(io.string).to have_tar_header_field(:uname, "nobody")
        expect(io.string).to have_tar_header_field(:gname, "nogroup")
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
          expect { writer.file "test.txt", from: source_path, size: actual_size }.not_to raise_error
        end
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
        expect(data).to have_tar_header_field(:size, content.bytesize.to_s(8).rjust(11, "0"))
      end

      it "pads with NUL bytes when writing less than declared size" do
        content = "short"
        declared_size = 100

        MiniTarball::Writer.use(io) do |writer|
          writer.file("test.txt", size: declared_size, **default_options) { |s| s.write(content) }
        end

        file_content = io.string[512, declared_size]
        expect(file_content[0, content.length]).to eq(content)
        expect(file_content[content.length..]).to eq("\0" * (declared_size - content.length))
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

      it "keeps archive aligned if the block raises" do
        writer = MiniTarball::Writer.new(io)

        expect {
          writer.file("bad.txt", size: 10, **default_options) { |_s| raise "boom" }
        }.to raise_error(RuntimeError, "boom")

        writer.file("good.txt", content: "ok", **default_options)
        writer.close

        skip(GnuTar.skip_message) unless GnuTar.available?

        Dir.mktmpdir do |temp_dir|
          tar_path = File.join(temp_dir, "test.tar")
          File.binwrite(tar_path, io.string)

          GnuTar.extract(tar_path, destination: temp_dir)
          expect(File.read(File.join(temp_dir, "good.txt"))).to eq("ok")
          expect(File.binread(File.join(temp_dir, "bad.txt"))).to eq("\0" * 10)
        end
      end

      it "keeps archive aligned if a seekable block raises without size" do
        writer = MiniTarball::Writer.new(io)

        expect {
          writer.file("bad.txt", **default_options) do |stream|
            stream.write("partial")
            raise "boom"
          end
        }.to raise_error(RuntimeError, "boom")

        writer.file("good.txt", content: "ok", **default_options)
        writer.close

        skip(GnuTar.skip_message) unless GnuTar.available?

        Dir.mktmpdir do |temp_dir|
          tar_path = File.join(temp_dir, "test.tar")
          File.binwrite(tar_path, io.string)

          GnuTar.extract(tar_path, destination: temp_dir)
          expect(File.read(File.join(temp_dir, "good.txt"))).to eq("ok")
          expect(File.read(File.join(temp_dir, "bad.txt"))).to eq("partial")
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

    it "appends trailing slash if missing" do
      MiniTarball::Writer.use(io) { |writer| writer.directory "mydir", **default_options }

      expect(io.string).to have_tar_header_field(:name, "mydir/")
    end

    it "preserves trailing slash if present" do
      MiniTarball::Writer.use(io) { |writer| writer.directory "mydir/", **default_options }

      expect(io.string).to have_tar_header_field(:name, "mydir/")
    end

    it "uses mode 0755 by default" do
      MiniTarball::Writer.use(io) { |writer| writer.directory "mydir" }

      expect(io.string).to have_tar_header_field(:mode, "0000755")
    end

    it "rejects path traversal" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.directory "../etc" }.to raise_error(MiniTarball::UnsafeNameError)
      end
    end

    it "rejects nil name with UnsafeNameError" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.directory nil }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Empty name not allowed/,
        )
      end
    end
  end

  describe "#symlink" do
    it "creates a symlink entry" do
      MiniTarball::Writer.use(io) do |writer|
        writer.symlink "link.txt", target: "target.txt", **default_options
      end

      expect(io.string).to have_tar_header_field(:name, "link.txt")
      expect(io.string).to have_tar_header_field(:typeflag, "2")
      expect(io.string).to have_tar_header_field(:linkname, "target.txt")
    end

    it "uses mode 0777 by default" do
      MiniTarball::Writer.use(io) { |writer| writer.symlink "link.txt", target: "target.txt" }

      expect(io.string).to have_tar_header_field(:mode, "0000777")
    end

    it "supports targets longer than 100 bytes" do
      long_target = "very/long/path/" + "a" * 100

      MiniTarball::Writer.use(io) do |writer|
        writer.file long_target, content: "content", **default_options
        writer.symlink "link.txt", target: long_target, **default_options
      end

      skip(GnuTar.skip_message) unless GnuTar.available?

      Dir.mktmpdir do |temp_dir|
        tar_path = File.join(temp_dir, "test.tar")
        File.binwrite(tar_path, io.string)

        GnuTar.extract(tar_path, destination: temp_dir)
        link_path = File.join(temp_dir, "link.txt")
        expect(File.symlink?(link_path)).to be true
        expect(File.readlink(link_path)).to eq(long_target)
      end
    end

    it "accepts targets at exactly 100 bytes" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.symlink "link.txt", target: "a" * 100 }.not_to raise_error
      end
    end

    it "rejects absolute target paths" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.symlink "link.txt", target: "/etc/passwd" }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Absolute target paths are not allowed/,
        )
      end
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
        expect {
          writer.symlink "subdir/link.txt",
                         target: "../sibling/file.txt",
                         allow_parent_references: true
        }.not_to raise_error
      end
    end

    it "rejects nil target" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.symlink "link.txt", target: nil }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Empty target not allowed/,
        )
      end
    end

    it "rejects empty target" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.symlink "link.txt", target: "" }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Empty target not allowed/,
        )
      end
    end
  end

  describe "#hardlink" do
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

      skip(GnuTar.skip_message) unless GnuTar.available?

      MiniTarball::Writer.use(io) do |writer|
        writer.file long_target, content: "content", **default_options
        writer.hardlink "link.txt", target: long_target, **default_options
      end

      Dir.mktmpdir do |temp_dir|
        tar_path = File.join(temp_dir, "test.tar")
        File.binwrite(tar_path, io.string)

        GnuTar.extract(tar_path, destination: temp_dir)
        expect(File.exist?(File.join(temp_dir, "link.txt"))).to be true
        expect(File.read(File.join(temp_dir, "link.txt"))).to eq("content")
      end
    end

    it "rejects absolute target paths" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.hardlink "link.txt", target: "/etc/passwd" }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Absolute target paths are not allowed/,
        )
      end
    end

    it "rejects path traversal in targets by default" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.hardlink "link.txt", target: "../other/file.txt" }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Path traversal is not allowed in target/,
        )
      end
    end

    it "allows path traversal when explicitly permitted" do
      MiniTarball::Writer.use(io) do |writer|
        writer.file "other/file.txt", content: "content", **default_options
        expect {
          writer.hardlink "link.txt", target: "../other/file.txt", allow_parent_references: true
        }.not_to raise_error
      end
    end
  end

  describe "#placeholder" do
    it "rejects absolute paths" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.placeholder "/etc/passwd", size: 100 }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Absolute paths are not allowed/,
        )
      end
    end

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

      expect(io.string).to have_tar_header_field(:name, "file1.txt")
    end

    it "recovers from exceptions in fill block" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "placeholder.txt", size: 100
        writer.file "file2.txt",
                    content: File.binread(fixture_path("files/file2.txt")),
                    **default_options

        expect { placeholder.fill { |_s| raise "simulated error" } }.to raise_error(
          RuntimeError,
          "simulated error",
        )

        placeholder.fill content: "ok", **default_options

        writer.file "file3.txt",
                    content: File.binread(fixture_path("files/file3.txt")),
                    **default_options
      end

      skip(GnuTar.skip_message) unless GnuTar.available?

      Dir.mktmpdir do |temp_dir|
        tar_path = File.join(temp_dir, "test.tar")
        File.binwrite(tar_path, io.string)

        GnuTar.extract(tar_path, destination: temp_dir)
        expect(File.exist?(File.join(temp_dir, "file3.txt"))).to be true
      end
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

    it "raises an error when placeholders are not filled" do
      writer = MiniTarball::Writer.new(io)
      writer.placeholder "file1.txt", size: 100

      expect { writer.close }.to raise_error(MiniTarball::UnfilledPlaceholderError)
      expect(writer.closed?).to eq(true)
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
end
