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

      expect(io.string).to have_tar_header_field(:uname, MiniTarball::Writer::DEFAULT_UNAME)
      expect(io.string).to have_tar_header_field(:gname, MiniTarball::Writer::DEFAULT_GNAME)
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
end
