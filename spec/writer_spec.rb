# frozen_string_literal: true

require "tempfile"
require "time"
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

  def add_files(writer, filenames)
    filenames.each do |filename|
      path = File.join(fixture_path("files"), filename)
      writer.add_file(name: filename, source_file_path: path)
    end
  end

  def add_files_from_stream(writer, filenames)
    filenames.each do |filename|
      path = File.join(fixture_path("files"), filename)
      add_file_from_stream(writer, path, filename)
    end
  end

  def add_file_from_stream(writer, path, filename)
    writer.add_file_from_stream(name: filename, **default_options) do |output_stream|
      File.open(path, "rb") { |input_stream| IO.copy_stream(input_stream, output_stream) }
    end
  end

  def with_temp_tar(filenames, fixture_directory: "files")
    Dir.mktmpdir do |temp_dir|
      output_filename = File.join(temp_dir, "test.tar")
      tar_binary = /darwin/ =~ RUBY_PLATFORM ? "gtar" : "tar"

      Dir.chdir(fixture_path(fixture_directory)) do
        system(
          tar_binary,
          "--format=gnu",
          "--blocking-factor=1",
          "-cf",
          output_filename,
          *filenames,
        )
      end

      yield(File.binread(output_filename))
    end
  end

  describe ".create" do
    it "creates a new tar file" do
      Tempfile.create do |temp_file|
        MiniTarball::Writer.create(temp_file.path) do |writer|
          add_files_from_stream(writer, %w[file1.txt file2.txt file3.txt])
        end

        expect(temp_file.binmode.read).to eq(fixture("archives/multiple_files.tar"))
      end
    end
  end

  describe ".use" do
    it "closes the stream when it's done" do
      expect(io).to_not be_closed

      MiniTarball::Writer.use(io) { |writer| add_files_from_stream(writer, %w[file1.txt]) }

      expect(io).to be_closed
    end
  end

  describe "#add_file" do
    let(:source_path) { fixture_path("files/file1.txt") }

    it "creates a valid tar with multiple files" do
      filenames = %w[file1.txt file2.txt file3.txt]

      MiniTarball::Writer.use(io) { |writer| add_files(writer, %w[file1.txt file2.txt file3.txt]) }

      with_temp_tar(filenames) { |tar| expect(io.string).to eq(tar) }
    end

    it "works with a non-seekable IO object" do
      filenames = %w[file1.txt file2.txt file3.txt]
      gzip = Zlib::GzipWriter.new(io)

      MiniTarball::Writer.use(gzip) { |writer| add_files(writer, filenames) }

      data = Zlib::GzipReader.new(StringIO.new(io.string, "rb")).read
      with_temp_tar(filenames) { |tar| expect(data).to eq(tar) }
    end

    it "rejects absolute paths" do
      MiniTarball::Writer.use(io) do |writer|
        expect {
          writer.add_file(name: "/etc/passwd", source_file_path: source_path)
        }.to raise_error(MiniTarball::UnsafeNameError, /Absolute paths are not allowed/)
      end
    end

    it "rejects path traversal" do
      MiniTarball::Writer.use(io) do |writer|
        expect {
          writer.add_file(name: "../etc/passwd", source_file_path: source_path)
        }.to raise_error(MiniTarball::UnsafeNameError, /Path traversal is not allowed/)

        expect {
          writer.add_file(name: "foo/../../../etc/passwd", source_file_path: source_path)
        }.to raise_error(MiniTarball::UnsafeNameError, /Path traversal is not allowed/)
      end
    end

    it "rejects bare .. as path traversal" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.add_file(name: "..", source_file_path: source_path) }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Path traversal is not allowed/,
        )
      end
    end

    it "rejects Windows absolute paths" do
      MiniTarball::Writer.use(io) do |writer|
        expect {
          writer.add_file(name: "C:\\Windows\\System32\\file.txt", source_file_path: source_path)
        }.to raise_error(MiniTarball::UnsafeNameError, /Absolute paths are not allowed/)

        expect {
          writer.add_file(name: "\\\\server\\share\\file.txt", source_file_path: source_path)
        }.to raise_error(MiniTarball::UnsafeNameError, /Absolute paths are not allowed/)
      end
    end

    it "rejects path traversal with backslashes" do
      MiniTarball::Writer.use(io) do |writer|
        expect {
          writer.add_file(name: "foo\\..\\..\\etc\\passwd", source_file_path: source_path)
        }.to raise_error(MiniTarball::UnsafeNameError, /Path traversal is not allowed/)
      end
    end

    it "rejects empty name" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.add_file(name: "", source_file_path: source_path) }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Empty name not allowed/,
        )
      end
    end

    it "allows relative paths without traversal" do
      MiniTarball::Writer.use(io) do |writer|
        expect {
          writer.add_file(name: "subdir/file.txt", source_file_path: source_path)
        }.not_to raise_error
      end
    end

    it "handles missing UID/GID gracefully" do
      allow(Etc).to receive(:getpwuid).and_raise(ArgumentError)
      allow(Etc).to receive(:getgrgid).and_raise(ArgumentError)

      MiniTarball::Writer.use(io) do |writer|
        writer.add_file(name: "test.txt", source_file_path: source_path)
      end

      expect(io.string).to have_tar_header_field(:uname, "nobody")
      expect(io.string).to have_tar_header_field(:gname, "nogroup")
    end
  end

  describe "#add_directory" do
    it "creates a directory entry" do
      MiniTarball::Writer.use(io) do |writer|
        writer.add_directory(name: "mydir", **default_options)
      end

      expect(io.string).to have_tar_header_field(:name, "mydir/")
      expect(io.string).to have_tar_header_field(:typeflag, "5")
    end

    it "appends trailing slash if missing" do
      MiniTarball::Writer.use(io) do |writer|
        writer.add_directory(name: "mydir", **default_options)
      end

      expect(io.string).to have_tar_header_field(:name, "mydir/")
    end

    it "preserves trailing slash if present" do
      MiniTarball::Writer.use(io) do |writer|
        writer.add_directory(name: "mydir/", **default_options)
      end

      expect(io.string).to have_tar_header_field(:name, "mydir/")
    end

    it "creates valid tar that extracts with system tar" do
      MiniTarball::Writer.use(io) do |writer|
        writer.add_directory(name: "testdir", **default_options)
      end

      Dir.mktmpdir do |temp_dir|
        tar_path = File.join(temp_dir, "test.tar")
        File.binwrite(tar_path, io.string)

        system("tar", "-xf", tar_path, "-C", temp_dir)
        expect(File.directory?(File.join(temp_dir, "testdir"))).to be true
      end
    end

    it "uses mode 0755 by default" do
      MiniTarball::Writer.use(io) { |writer| writer.add_directory(name: "mydir") }

      expect(io.string).to have_tar_header_field(:mode, "0000755")
    end

    it "rejects path traversal" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.add_directory(name: "../etc") }.to raise_error(MiniTarball::UnsafeNameError)
      end
    end
  end

  describe "#add_symlink" do
    it "creates a symlink entry" do
      MiniTarball::Writer.use(io) do |writer|
        writer.add_symlink(name: "link.txt", target: "target.txt", **default_options)
      end

      expect(io.string).to have_tar_header_field(:name, "link.txt")
      expect(io.string).to have_tar_header_field(:typeflag, "2")
      expect(io.string).to have_tar_header_field(:linkname, "target.txt")
    end

    it "uses mode 0777 by default" do
      MiniTarball::Writer.use(io) do |writer|
        writer.add_symlink(name: "link.txt", target: "target.txt")
      end

      expect(io.string).to have_tar_header_field(:mode, "0000777")
    end

    it "creates valid tar that extracts with system tar" do
      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: "target.txt", **default_options) do |s|
          s.write("content")
        end
        writer.add_symlink(name: "link.txt", target: "target.txt", **default_options)
      end

      Dir.mktmpdir do |temp_dir|
        tar_path = File.join(temp_dir, "test.tar")
        File.binwrite(tar_path, io.string)

        system("tar", "-xf", tar_path, "-C", temp_dir)
        expect(File.symlink?(File.join(temp_dir, "link.txt"))).to be true
        expect(File.readlink(File.join(temp_dir, "link.txt"))).to eq("target.txt")
      end
    end

    it "supports targets longer than 100 bytes" do
      long_target = "very/long/path/" + "a" * 100

      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: long_target, **default_options) { |s| s.write("content") }
        writer.add_symlink(name: "link.txt", target: long_target, **default_options)
      end

      Dir.mktmpdir do |temp_dir|
        tar_path = File.join(temp_dir, "test.tar")
        File.binwrite(tar_path, io.string)

        system("tar", "-xf", tar_path, "-C", temp_dir)
        link_path = File.join(temp_dir, "link.txt")
        expect(File.symlink?(link_path)).to be true
        expect(File.readlink(link_path)).to eq(long_target)
      end
    end

    it "accepts targets at exactly 100 bytes" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.add_symlink(name: "link.txt", target: "a" * 100) }.not_to raise_error
      end
    end

    it "rejects absolute target paths" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.add_symlink(name: "link.txt", target: "/etc/passwd") }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Absolute target paths are not allowed/,
        )
      end
    end

    it "rejects Windows absolute target paths" do
      MiniTarball::Writer.use(io) do |writer|
        expect {
          writer.add_symlink(name: "link.txt", target: "C:\\Windows\\System32")
        }.to raise_error(MiniTarball::UnsafeNameError, /Absolute target paths are not allowed/)
      end
    end

    it "allows relative targets with .." do
      MiniTarball::Writer.use(io) do |writer|
        # Relative targets with .. are valid (pointing to sibling directories)
        expect {
          writer.add_symlink(name: "subdir/link.txt", target: "../sibling/file.txt")
        }.not_to raise_error
      end
    end
  end

  describe "#add_hardlink" do
    it "creates a hardlink entry" do
      MiniTarball::Writer.use(io) do |writer|
        writer.add_hardlink(name: "link.txt", target: "target.txt", **default_options)
      end

      expect(io.string).to have_tar_header_field(:name, "link.txt")
      expect(io.string).to have_tar_header_field(:typeflag, "1")
      expect(io.string).to have_tar_header_field(:linkname, "target.txt")
    end

    it "creates valid tar that extracts with system tar" do
      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: "target.txt", **default_options) do |s|
          s.write("content")
        end
        writer.add_hardlink(name: "link.txt", target: "target.txt", **default_options)
      end

      Dir.mktmpdir do |temp_dir|
        tar_path = File.join(temp_dir, "test.tar")
        File.binwrite(tar_path, io.string)

        system("tar", "-xf", tar_path, "-C", temp_dir)
        expect(File.exist?(File.join(temp_dir, "link.txt"))).to be true
        expect(File.read(File.join(temp_dir, "link.txt"))).to eq("content")
      end
    end

    it "supports targets longer than 100 bytes" do
      long_target = "very/long/path/" + "a" * 100

      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: long_target, **default_options) { |s| s.write("content") }
        writer.add_hardlink(name: "link.txt", target: long_target, **default_options)
      end

      Dir.mktmpdir do |temp_dir|
        tar_path = File.join(temp_dir, "test.tar")
        File.binwrite(tar_path, io.string)

        system("tar", "-xf", tar_path, "-C", temp_dir)
        expect(File.exist?(File.join(temp_dir, "link.txt"))).to be true
        expect(File.read(File.join(temp_dir, "link.txt"))).to eq("content")
      end
    end

    it "rejects absolute target paths" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.add_hardlink(name: "link.txt", target: "/etc/passwd") }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Absolute target paths are not allowed/,
        )
      end
    end

    it "rejects Windows absolute target paths" do
      MiniTarball::Writer.use(io) do |writer|
        expect {
          writer.add_hardlink(name: "link.txt", target: "C:\\important\\file")
        }.to raise_error(MiniTarball::UnsafeNameError, /Absolute target paths are not allowed/)
      end
    end
  end

  describe "#add_file_from_stream" do
    it "creates a valid tar with multiple files" do
      MiniTarball::Writer.use(io) do |writer|
        add_files_from_stream(writer, %w[file1.txt file2.txt file3.txt])
      end

      expect(io.string).to eq(fixture("archives/multiple_files.tar"))
    end

    it "raises an error when a non-seekable IO object is used" do
      gzip = Zlib::GzipWriter.new(io)

      MiniTarball::Writer.use(gzip) do |writer|
        expect { add_files_from_stream(writer, %w[file1.txt]) }.to raise_error(
          MiniTarball::NotSeekableError,
        )
      end
    end

    it "rejects absolute paths" do
      MiniTarball::Writer.use(io) do |writer|
        expect {
          writer.add_file_from_stream(name: "/etc/passwd") { |s| s.write("x") }
        }.to raise_error(MiniTarball::UnsafeNameError, /Absolute paths are not allowed/)
      end
    end

    it "rejects path traversal" do
      MiniTarball::Writer.use(io) do |writer|
        expect {
          writer.add_file_from_stream(name: "../passwd") { |s| s.write("x") }
        }.to raise_error(MiniTarball::UnsafeNameError, /Path traversal is not allowed/)
      end
    end

    context "with size: parameter (non-seekable streams)" do
      it "works with gzip when size is provided" do
        gzip = Zlib::GzipWriter.new(io)
        content = "Hello, World!"

        MiniTarball::Writer.use(gzip) do |writer|
          writer.add_file_from_stream(
            name: "test.txt",
            size: content.bytesize,
            **default_options,
          ) { |s| s.write(content) }
        end

        data = Zlib::GzipReader.new(StringIO.new(io.string, "rb")).read
        expect(data).to have_tar_header_field(:name, "test.txt")
        expect(data).to have_tar_header_field(:size, content.bytesize.to_s(8).rjust(11, "0"))
      end

      it "pads with NUL bytes when writing less than declared size" do
        content = "short"
        declared_size = 100

        MiniTarball::Writer.use(io) do |writer|
          writer.add_file_from_stream(
            name: "test.txt",
            size: declared_size,
            **default_options,
          ) { |s| s.write(content) }
        end

        # File content starts after 512-byte header
        file_content = io.string[512, declared_size]
        expect(file_content[0, content.length]).to eq(content)
        expect(file_content[content.length..]).to eq("\0" * (declared_size - content.length))
      end

      it "raises error when writing more than declared size" do
        MiniTarball::Writer.use(io) do |writer|
          expect {
            writer.add_file_from_stream(name: "test.txt", size: 5, **default_options) do |s|
              s.write("too long!")
            end
          }.to raise_error(MiniTarball::WriteOutOfRangeError)
        end
      end

      it "creates valid tar that extracts correctly with gzip" do
        Dir.mktmpdir do |temp_dir|
          tar_gz_path = File.join(temp_dir, "test.tar.gz")
          extract_dir = File.join(temp_dir, "extracted")
          Dir.mkdir(extract_dir)

          File.open(tar_gz_path, "wb") do |file|
            gzip = Zlib::GzipWriter.new(file)
            MiniTarball::Writer.use(gzip) do |writer|
              writer.add_file_from_stream(name: "hello.txt", size: 13, **default_options) do |s|
                s.write("Hello, World!")
              end
            end
          end

          tar_binary = /darwin/ =~ RUBY_PLATFORM ? "gtar" : "tar"
          system(tar_binary, "-xzf", tar_gz_path, "-C", extract_dir)

          expect(File.read(File.join(extract_dir, "hello.txt"))).to eq("Hello, World!")
        end
      end
    end

    it "handles filename at exactly 100 bytes (no long link needed)" do
      name = "a" * 100

      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name:, **default_options) { |s| s.write("test") }
      end

      expect(io.string).to have_tar_header_field(:name, name)
    end

    it "handles filename at 101 bytes (requires long link)" do
      name = "a" * 101

      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name:, **default_options) { |s| s.write("test") }
      end

      # Long link header should be present (././@LongLink)
      expect(io.string).to have_tar_header_field(:name, "././@LongLink")
    end

    it "handles binary content with null bytes" do
      binary_content = "\x00\x01\x02\x03\x00\xFF\xFE\x00".b

      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: "binary.bin", **default_options) do |s|
          s.write(binary_content)
        end
      end

      # Extract the file content from the tar (after 512-byte header)
      file_content = io.string.b[512, binary_content.bytesize]
      expect(file_content).to eq(binary_content)
    end
  end

  describe "#add_file_placeholder" do
    it "rejects absolute paths" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.add_file_placeholder(name: "/etc/passwd", size: 100) }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Absolute paths are not allowed/,
        )
      end
    end

    it "rejects path traversal" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.add_file_placeholder(name: "foo/../../passwd", size: 100) }.to raise_error(
          MiniTarball::UnsafeNameError,
          /Path traversal is not allowed/,
        )
      end
    end
  end

  describe "Placeholder#fill" do
    it "adds file at the beginning of tar file" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder =
          writer.add_file_placeholder(
            name: "file1.txt",
            size: File.size(fixture_path("files/file1.txt")),
          )
        add_files_from_stream(writer, %w[file2.txt file3.txt])

        placeholder.fill { |w| add_files_from_stream(w, %w[file1.txt]) }
      end

      expect(io.string).to eq(fixture("archives/multiple_files.tar"))
    end

    it "adds file in the middle of tar file" do
      MiniTarball::Writer.use(io) do |writer|
        add_files_from_stream(writer, %w[file1.txt])
        placeholder =
          writer.add_file_placeholder(
            name: "file2.txt",
            size: File.size(fixture_path("files/file2.txt")),
          )
        add_files_from_stream(writer, %w[file3.txt])

        placeholder.fill { |w| add_files_from_stream(w, %w[file2.txt]) }
      end

      expect(io.string).to eq(fixture("archives/multiple_files.tar"))
    end

    it "supports adding multiple files via placeholder" do
      MiniTarball::Writer.use(io) do |writer|
        add_files(writer, %w[file1.txt])
        placeholder2 =
          writer.add_file_placeholder(
            name: "file2.txt",
            size: File.size(fixture_path("files/file2.txt")),
          )
        placeholder3 =
          writer.add_file_placeholder(
            name: "file3.txt",
            size: File.size(fixture_path("files/file3.txt")),
          )

        placeholder2.fill { |w| add_files(w, %w[file2.txt]) }
        placeholder3.fill { |w| add_files(w, %w[file3.txt]) }
      end

      with_temp_tar(%w[file1.txt file2.txt file3.txt]) { |tar| expect(io.string).to eq(tar) }
    end

    it "supports adding a file that is smaller than the placeholder" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder =
          writer.add_file_placeholder(
            name: "file1.txt",
            size: File.size(fixture_path("files/file1.txt")) + 1492,
          )

        placeholder.fill { |w| add_files_from_stream(w, %w[file1.txt]) }

        add_files_from_stream(writer, %w[file2.txt])
      end

      expect(io.string).to eq(fixture("archives/small_file_in_large_placeholder.tar"))
    end

    it "raises an error if the file is larger than the placeholder" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder =
          writer.add_file_placeholder(
            name: "file1.txt",
            size: File.size(fixture_path("files/file1.txt")) - 100,
          )

        placeholder.fill do |w|
          expect { add_files_from_stream(w, %w[file1.txt]) }.to raise_error(
            MiniTarball::WriteOutOfRangeError,
          )
        end
      end
    end

    it "raises an error when a non-seekable IO object is used" do
      gzip = Zlib::GzipWriter.new(io)

      MiniTarball::Writer.use(gzip) do |writer|
        placeholder =
          writer.add_file_placeholder(
            name: "file1.txt",
            size: File.size(fixture_path("files/file1.txt")),
          )

        expect { placeholder.fill {} }.to raise_error(MiniTarball::NotSeekableError)
      end
    end

    it "supports filling placeholders in any order" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder1 = writer.add_file_placeholder(name: "file1.txt", size: 100)
        placeholder2 = writer.add_file_placeholder(name: "file2.txt", size: 100)

        # Fill placeholder2 first, then placeholder1
        placeholder2.fill do |w|
          w.add_file_from_stream(name: "file2.txt", **default_options) { |s| s.write("content2") }
        end

        placeholder1.fill do |w|
          w.add_file_from_stream(name: "file1.txt", **default_options) { |s| s.write("content1") }
        end
      end

      expect(io.string).to have_tar_header_field(:name, "file1.txt")
    end

    it "raises an error if placeholder is filled twice" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.add_file_placeholder(name: "file1.txt", size: 100)

        placeholder.fill do |w|
          w.add_file_from_stream(name: "file1.txt", **default_options) { |s| s.write("content") }
        end

        expect { placeholder.fill {} }.to raise_error(ArgumentError, /already filled/)
      end
    end

    it "returns the writer for chaining" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.add_file_placeholder(name: "file1.txt", size: 100)
        result =
          placeholder.fill do |w|
            w.add_file_from_stream(name: "f.txt", **default_options) { |s| s.write("x") }
          end
        expect(result).to eq(writer)
      end
    end
  end

  describe "#close" do
    it "creates a valid tar file when manually closing the writer" do
      writer = MiniTarball::Writer.new(io)
      add_files_from_stream(writer, %w[file1.txt file2.txt file3.txt])
      expect(writer.closed?).to eq(false)

      writer.close

      expect(writer.closed?).to eq(true)
      expect { add_files_from_stream(writer, %w[file1.txt]) }.to raise_error(IOError)
      expect(io.string).to eq(fixture("archives/multiple_files.tar"))
    end

    it "raises an error when closing an already-closed writer" do
      writer = MiniTarball::Writer.new(io)
      writer.close

      expect { writer.close }.to raise_error(IOError)
    end
  end

  it "raises an error when no valid IO object is used" do
    expect { MiniTarball::Writer.new(Object.new) }.to raise_error(MiniTarball::NoIOLikeObjectError)
  end

  describe "integration: extraction with system tar" do
    it "creates archives that can be extracted by system tar" do
      Dir.mktmpdir do |temp_dir|
        tar_path = File.join(temp_dir, "test.tar")
        extract_dir = File.join(temp_dir, "extracted")
        Dir.mkdir(extract_dir)

        # Create a tar file with our Writer
        MiniTarball::Writer.create(tar_path) do |writer|
          writer.add_file_from_stream(name: "hello.txt", **default_options) do |stream|
            stream.write("Hello, World!")
          end
          writer.add_file_from_stream(name: "subdir/nested.txt", **default_options) do |stream|
            stream.write("Nested content")
          end
        end

        # Extract with system tar
        tar_binary = /darwin/ =~ RUBY_PLATFORM ? "gtar" : "tar"
        system(tar_binary, "-xf", tar_path, "-C", extract_dir)

        # Verify extracted contents
        expect(File.read(File.join(extract_dir, "hello.txt"))).to eq("Hello, World!")
        expect(File.read(File.join(extract_dir, "subdir/nested.txt"))).to eq("Nested content")
      end
    end
  end
end
