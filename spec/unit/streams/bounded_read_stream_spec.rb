# frozen_string_literal: true

RSpec.describe MiniTarball::BoundedReadStream do
  let(:data) { "Hello, World!" }
  let(:io) { StringIO.new(data) }
  let(:stream) { described_class.new(io, data.bytesize) }

  describe "#read" do
    it "reads the entire content when no length specified" do
      expect(stream.read).to eq(data)
      expect(stream.bytes_read).to eq(data.bytesize)
    end

    it "reads specified number of bytes" do
      expect(stream.read(5)).to eq("Hello")
      expect(stream.bytes_read).to eq(5)
    end

    it "reads into provided buffer" do
      buffer = +""
      result = stream.read(5, buffer)

      expect(result).to be(buffer)
      expect(buffer).to eq("Hello")
    end

    it "returns nil at end of entry" do
      stream.read
      expect(stream.read).to be_nil
    end

    it "returns empty string for read(0)" do
      expect(stream.read(0)).to eq("")
    end

    it "does not read beyond the size limit" do
      extra_data = "Hello, World! Extra data beyond limit"
      io = StringIO.new(extra_data)
      stream = described_class.new(io, 13) # Only "Hello, World!"

      expect(stream.read).to eq("Hello, World!")
      expect(stream.read).to be_nil
    end

    it "raises TruncatedArchiveError when IO has less data than expected" do
      io = StringIO.new("short")
      stream = described_class.new(io, 100)

      expect { stream.read }.to raise_error(MiniTarball::TruncatedArchiveError)
    end

    it "raises TruncatedArchiveError when length read is short" do
      io = StringIO.new("sho")
      stream = described_class.new(io, 10)

      expect { stream.read(5) }.to raise_error(MiniTarball::TruncatedArchiveError)
    end
  end

  describe "#gets" do
    let(:multiline_data) { "line1\nline2\nline3" }
    let(:io) { StringIO.new(multiline_data) }
    let(:stream) { described_class.new(io, multiline_data.bytesize) }

    it "reads a single line" do
      expect(stream.gets).to eq("line1\n")
    end

    it "reads subsequent lines" do
      stream.gets
      expect(stream.gets).to eq("line2\n")
    end

    it "returns nil at end of entry" do
      3.times { stream.gets }
      expect(stream.gets).to be_nil
    end

    it "respects the limit parameter" do
      expect(stream.gets("\n", 3)).to eq("lin")
    end
  end

  describe "#each_byte" do
    it "iterates over each byte" do
      bytes = []
      stream.each_byte { |b| bytes << b }

      expect(bytes).to eq(data.bytes)
    end

    it "returns an Enumerator when no block given" do
      expect(stream.each_byte).to be_an(Enumerator)
      expect(stream.each_byte.to_a).to eq(data.bytes)
    end
  end

  describe "#remaining" do
    it "returns the full size initially" do
      expect(stream.remaining).to eq(data.bytesize)
    end

    it "decreases as data is read" do
      stream.read(5)
      expect(stream.remaining).to eq(data.bytesize - 5)
    end

    it "returns 0 when all data is read" do
      stream.read
      expect(stream.remaining).to eq(0)
    end
  end

  describe "#eof?" do
    it "returns false initially" do
      expect(stream.eof?).to be false
    end

    it "returns true after reading all data" do
      stream.read
      expect(stream.eof?).to be true
    end
  end

  describe "#skip" do
    it "skips remaining bytes" do
      stream.read(5)
      stream.skip

      expect(stream.bytes_read).to eq(data.bytesize)
      expect(stream.eof?).to be true
    end

    it "works with seekable IO" do
      stream.skip

      expect(stream.eof?).to be true
      expect(io.pos).to eq(data.bytesize)
    end

    it "raises TruncatedArchiveError when seekable IO is too short" do
      io = StringIO.new("short")
      stream = described_class.new(io, 100)

      expect { stream.skip }.to raise_error(MiniTarball::TruncatedArchiveError)
    end

    it "works with non-seekable IO" do
      # Simulate non-seekable IO by removing seek method
      non_seekable =
        Class
          .new do
            def initialize(data)
              @io = StringIO.new(data)
            end

            def read(length, buffer = nil)
              @io.read(length, buffer)
            end
          end
          .new(data)

      stream = described_class.new(non_seekable, data.bytesize)
      stream.skip

      expect(stream.eof?).to be true
    end
  end

  describe "#copy_to" do
    it "copies content to destination IO" do
      dest = StringIO.new
      copied = stream.copy_to(dest)

      expect(copied).to eq(data.bytesize)
      expect(dest.string).to eq(data)
    end
  end
end
