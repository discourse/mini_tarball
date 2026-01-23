# frozen_string_literal: true

RSpec.describe MiniTarball::Header do
  describe "#has_long_name?" do
    it "returns false for names at exactly 100 bytes" do
      header = described_class.new(name: "a" * 100)
      expect(header.has_long_name?).to be false
    end

    it "returns true for names over 100 bytes" do
      header = described_class.new(name: "a" * 101)
      expect(header.has_long_name?).to be true
    end

    it "returns false for short names" do
      header = described_class.new(name: "file.txt")
      expect(header.has_long_name?).to be false
    end

    it "counts bytes not characters for multibyte names" do
      # 34 chars × 3 bytes = 102 bytes
      header = described_class.new(name: "日" * 34)
      expect(header.has_long_name?).to be true
    end
  end

  describe "#to_binary" do
    it "returns a 512-byte block" do
      header = described_class.new(name: "test.txt")
      expect(header.to_binary.bytesize).to eq(512)
    end

    it "includes the filename at the start" do
      header = described_class.new(name: "test.txt")
      binary = header.to_binary
      expect(binary[0, 8]).to eq("test.txt")
    end

    it "includes the magic string" do
      header = described_class.new(name: "test.txt")
      binary = header.to_binary
      # Magic is at offset 257 (after name, mode, uid, gid, size, mtime, checksum, typeflag, linkname)
      expect(binary[257, 6]).to eq("ustar ")
    end
  end

  describe ".long_link_header" do
    it "creates a header for long link entries" do
      header = described_class.long_link_header("a" * 200)

      expect(header.value_of(:name)).to eq("././@LongLink")
      expect(header.value_of(:typeflag)).to eq(MiniTarball::Header::TYPE_LONG_LINK)
      expect(header.value_of(:size)).to eq(201) # name length + 1 for null terminator
    end
  end

  describe "FIELDS" do
    it "is frozen" do
      expect(MiniTarball::Header::FIELDS).to be_frozen
    end

    it "has frozen nested hashes" do
      MiniTarball::Header::FIELDS.each_value { |field| expect(field).to be_frozen }
    end

    it "defines correct total header size" do
      total = MiniTarball::Header::FIELDS.values.sum { |f| f[:length] }
      expect(total).to eq(500) # 512 - 12 bytes padding
    end
  end

  describe "TYPE constants" do
    it "defines TYPE_REGULAR" do
      expect(MiniTarball::Header::TYPE_REGULAR).to eq("0")
    end

    it "defines TYPE_LONG_LINK" do
      expect(MiniTarball::Header::TYPE_LONG_LINK).to eq("L")
    end
  end
end
