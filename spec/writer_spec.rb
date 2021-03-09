# frozen_string_literal: true

require 'tempfile'
require 'time'

RSpec.describe MiniTarball::Writer do
  let(:io) { StringIO.new.binmode }

  let!(:default_options) do
    {
      mode: 0644,
      mtime: Time.parse("2021-02-15T20:11:34Z"),
      uname: "discourse",
      gname: "www-data",
      uid: 1001,
      gid: 33
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
      writer.add_file_from_stream(name: filename, **default_options) do |output_stream|
        path = File.join(fixture_path("files"), filename)

        File.open(path, "rb") do |input_stream|
          IO.copy_stream(input_stream, output_stream)
        end
      end
    end
  end

  def with_temp_tar(filenames)
    Dir.mktmpdir do |temp_dir|
      output_filename = File.join(temp_dir, "test.tar")
      filenames = filenames.join(" ")
      options = "--format=gnu --blocking-factor=1"

      Dir.chdir(fixture_path("files")) do
        `tar #{options} -cf #{output_filename} #{filenames}`
      end

      yield(IO.binread(output_filename))
    end
  end

  describe ".create" do
    it "creates a new tar file" do
      Tempfile.create do |temp_file|
        MiniTarball::Writer.create(temp_file.path) do |writer|
          add_files_from_stream(writer, %w{file1.txt file2.txt file3.txt})
        end

        expect(temp_file.binmode.read).to eq(fixture("archives/multiple_files.tar"))
      end
    end
  end

  describe ".use" do
    it "closes the stream when it's done" do
      expect(io).to_not be_closed

      MiniTarball::Writer.use(io) do |writer|
        add_files_from_stream(writer, %w{file1.txt})
      end

      expect(io).to be_closed
    end
  end

  describe "#add_file" do
    it "creates a valid tar with multiple files" do
      filenames = %w{file1.txt file2.txt file3.txt}

      MiniTarball::Writer.use(io) do |writer|
        add_files(writer, %w{file1.txt file2.txt file3.txt})
      end

      with_temp_tar(filenames) do |tar|
        expect(io.string).to eq(tar)
      end
    end
  end

  describe "#add_file_from_stream" do
    it "creates a valid tar with multiple files" do
      MiniTarball::Writer.use(io) do |writer|
        add_files_from_stream(writer, %w{file1.txt file2.txt file3.txt})
      end

      expect(io.string).to eq(fixture("archives/multiple_files.tar"))
    end
  end

  describe "#close" do
    it "creates a valid tar file when manually closing the writer" do
      writer = MiniTarball::Writer.new(io)
      add_files_from_stream(writer, %w{file1.txt file2.txt file3.txt})
      expect(writer.closed?).to eq(false)

      writer.close

      expect(writer.closed?).to eq(true)
      expect { add_files_from_stream(writer, %w{file1.txt}) }.to raise_error(IOError)
      expect(io.string).to eq(fixture("archives/multiple_files.tar"))
    end
  end
end
