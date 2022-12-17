# frozen_string_literal: true

require "tempfile"
require "time"

RSpec.describe MiniTarball::Writer do
  let(:io) { StringIO.new.binmode }

  let!(:default_options) do
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
      add_file_from_steam(writer, path, filename)
    end
  end

  def add_file_from_steam(writer, path, filename)
    writer.add_file_from_stream(name: filename, **default_options) do |output_stream|
      File.open(path, "rb") { |input_stream| IO.copy_stream(input_stream, output_stream) }
    end
  end

  def with_temp_tar(filenames, fixture_directory: "files")
    Dir.mktmpdir do |temp_dir|
      output_filename = File.join(temp_dir, "test.tar")
      filenames = filenames.join(" ")
      options = "--format=gnu --blocking-factor=1"
      tar_binary = /darwin/ =~ RUBY_PLATFORM ? "gtar" : "tar"

      Dir.chdir(fixture_path(fixture_directory)) do
        `#{tar_binary} #{options} -cf #{output_filename} #{filenames}`
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
    it "creates a valid tar with multiple files" do
      filenames = %w[file1.txt file2.txt file3.txt]

      MiniTarball::Writer.use(io) { |writer| add_files(writer, %w[file1.txt file2.txt file3.txt]) }

      with_temp_tar(filenames) { |tar| expect(io.string).to eq(tar) }
    end
  end

  describe "#add_file_from_stream" do
    it "creates a valid tar with multiple files" do
      MiniTarball::Writer.use(io) do |writer|
        add_files_from_stream(writer, %w[file1.txt file2.txt file3.txt])
      end

      expect(io.string).to eq(fixture("archives/multiple_files.tar"))
    end
  end

  describe "#with_placeholder" do
    it "raises an error if the placeholder doesn't exist" do
      MiniTarball::Writer.use(io) do |writer|
        expect { writer.with_placeholder(42) }.to raise_error(ArgumentError)
      end
    end

    it "adds file at the beginning of tar file" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder =
          writer.add_file_placeholder(
            name: "file1.txt",
            file_size: File.size(fixture_path("files/file1.txt")),
          )
        add_files_from_stream(writer, %w[file2.txt file3.txt])

        writer.with_placeholder(placeholder) { |w| add_files_from_stream(w, %w[file1.txt]) }
      end

      expect(io.string).to eq(fixture("archives/multiple_files.tar"))
    end

    it "adds file in the middle of tar file" do
      MiniTarball::Writer.use(io) do |writer|
        add_files_from_stream(writer, %w[file1.txt])
        placeholder =
          writer.add_file_placeholder(
            name: "file2.txt",
            file_size: File.size(fixture_path("files/file2.txt")),
          )
        add_files_from_stream(writer, %w[file3.txt])

        writer.with_placeholder(placeholder) { |w| add_files_from_stream(w, %w[file2.txt]) }
      end

      expect(io.string).to eq(fixture("archives/multiple_files.tar"))
    end

    it "supports adding multiple files via placeholder" do
      MiniTarball::Writer.use(io) do |writer|
        add_files(writer, %w[file1.txt])
        placeholder2 =
          writer.add_file_placeholder(
            name: "file2.txt",
            file_size: File.size(fixture_path("files/file2.txt")),
          )
        placeholder3 =
          writer.add_file_placeholder(
            name: "file3.txt",
            file_size: File.size(fixture_path("files/file3.txt")),
          )

        writer.with_placeholder(placeholder2) { |w| add_files(w, %w[file2.txt]) }

        writer.with_placeholder(placeholder3) { |w| add_files(w, %w[file3.txt]) }
      end

      with_temp_tar(%w[file1.txt file2.txt file3.txt]) { |tar| expect(io.string).to eq(tar) }
    end

    it "supports adding a file that is smaller than the placeholder" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder =
          writer.add_file_placeholder(
            name: "file1.txt",
            file_size: File.size(fixture_path("files/file1.txt")) + 1492,
          )

        writer.with_placeholder(placeholder) { |w| add_files_from_stream(w, %w[file1.txt]) }

        add_files_from_stream(writer, %w[file2.txt])
      end

      expect(io.string).to eq(fixture("archives/small_file_in_large_placeholder.tar"))
    end

    it "raises an error if the file is larger than the placeholder" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder =
          writer.add_file_placeholder(
            name: "file1.txt",
            file_size: File.size(fixture_path("files/file1.txt")) - 100,
          )

        writer.with_placeholder(placeholder) do |w|
          expect { add_files_from_stream(w, %w[file1.txt]) }.to raise_error(
            MiniTarball::WriteOutOfRangeError,
          )
        end
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
  end
end
