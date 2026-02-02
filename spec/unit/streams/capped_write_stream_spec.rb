# frozen_string_literal: true

RSpec.describe MiniTarball::CappedWriteStream do
  subject(:stream) { described_class.new(io, max_size:) }

  let(:io) { StringIO.new.binmode }
  let(:max_size) { 100 }

  describe "#write" do
    it "writes data to the underlying IO" do
      stream.write("hello")
      expect(io.string).to eq("hello")
    end

    it "tracks bytes written" do
      stream.write("hello")
      expect(stream.bytes_written).to eq(5)

      stream.write("world")
      expect(stream.bytes_written).to eq(10)
    end

    it "raises error when exceeding max size" do
      expect { stream.write("a" * 101) }.to raise_error(MiniTarball::WriteOutOfRangeError)
    end

    it "raises error when cumulative writes exceed max size" do
      stream.write("a" * 50)
      stream.write("b" * 50)

      expect { stream.write("c") }.to raise_error(MiniTarball::WriteOutOfRangeError)
    end

    it "allows writes up to exactly max size" do
      expect { stream.write("a" * 100) }.not_to raise_error
      expect(stream.bytes_written).to eq(100)
    end
  end

  describe "#<<" do
    it "writes data and returns self for chaining" do
      result = stream << "hello"
      expect(result).to eq(stream)
      expect(io.string).to eq("hello")
    end
  end

  describe "#remaining" do
    it "returns remaining bytes that can be written" do
      expect(stream.remaining).to eq(100)

      stream.write("a" * 30)
      expect(stream.remaining).to eq(70)
    end
  end
end
