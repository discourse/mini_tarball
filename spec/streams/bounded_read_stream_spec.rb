# frozen_string_literal: true

RSpec.describe MiniTarball::BoundedReadStream do
  let(:data) { "Hello, World!" }
  let(:io) { StringIO.new(data) }

  describe "#read" do
    it "reads up to the bounded size" do
      stream = described_class.new(io, size: 5)
      expect(stream.read).to eq("Hello")
    end

    it "reads specified length within bounds" do
      stream = described_class.new(io, size: 10)
      expect(stream.read(3)).to eq("Hel")
      expect(stream.read(3)).to eq("lo,")
    end

    it "limits read to remaining bytes" do
      stream = described_class.new(io, size: 5)
      expect(stream.read(100)).to eq("Hello")
    end

    it "returns nil when exhausted" do
      stream = described_class.new(io, size: 5)
      stream.read
      expect(stream.read).to be_nil
    end

    it "supports buffer argument" do
      stream = described_class.new(io, size: 5)
      buffer = +""
      result = stream.read(3, buffer)
      expect(result).to eq("Hel")
      expect(buffer).to eq("Hel")
    end
  end

  describe "#eof?" do
    it "returns false when bytes remain" do
      stream = described_class.new(io, size: 5)
      expect(stream.eof?).to be false
    end

    it "returns true when exhausted" do
      stream = described_class.new(io, size: 5)
      stream.read
      expect(stream.eof?).to be true
    end
  end

  describe "#remaining" do
    it "returns initial size before any reads" do
      stream = described_class.new(io, size: 10)
      expect(stream.remaining).to eq(10)
    end

    it "decreases after reads" do
      stream = described_class.new(io, size: 10)
      stream.read(3)
      expect(stream.remaining).to eq(7)
    end
  end

  describe "#size" do
    it "returns the total size" do
      stream = described_class.new(io, size: 10)
      expect(stream.size).to eq(10)
    end

    it "remains constant after reads" do
      stream = described_class.new(io, size: 10)
      stream.read(5)
      expect(stream.size).to eq(10)
    end
  end

  describe "#pos" do
    it "returns 0 before any reads" do
      stream = described_class.new(io, size: 10)
      expect(stream.pos).to eq(0)
    end

    it "returns bytes read so far" do
      stream = described_class.new(io, size: 10)
      stream.read(3)
      expect(stream.pos).to eq(3)
      stream.read(4)
      expect(stream.pos).to eq(7)
    end

    it "is aliased as tell" do
      stream = described_class.new(io, size: 10)
      stream.read(5)
      expect(stream.tell).to eq(5)
    end
  end
end
