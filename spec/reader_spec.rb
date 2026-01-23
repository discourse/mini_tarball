# frozen_string_literal: true

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
end
