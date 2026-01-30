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

    it "encodes the filename" do
      header = described_class.new(name: "test.txt")
      expect(header.to_binary).to have_tar_header_field(:name, "test.txt")
    end

    it "encodes the magic string" do
      header = described_class.new(name: "test.txt")
      expect(header.to_binary).to have_tar_header_field(:magic, "ustar")
    end

    it "produces a valid checksum" do
      header = described_class.new(name: "test.txt", size: 1024, mode: 0644)
      binary = header.to_binary

      # Checksum is calculated with the checksum field treated as spaces
      checksum_offset = 148
      bytes_with_spaces = binary[0, checksum_offset] + (" " * 8) + binary[checksum_offset + 8..]
      expected_checksum = bytes_with_spaces.bytes.sum

      # Extract stored checksum (octal string at offset 148, 8 bytes)
      stored_checksum = binary[checksum_offset, 8].strip.to_i(8)
      expect(stored_checksum).to eq(expected_checksum)
    end

    it "encodes mode as octal" do
      header = described_class.new(name: "test.txt", mode: 0755)
      expect(header.to_binary).to have_tar_header_field(:mode, "0000755")
    end

    it "encodes size as octal" do
      header = described_class.new(name: "test.txt", size: 4096)
      expect(header.to_binary).to have_tar_header_field(:size, "00000010000")
    end

    it "encodes typeflag for directories" do
      header = described_class.new(name: "mydir/", typeflag: MiniTarball::Header::TYPE_DIRECTORY)
      expect(header.to_binary).to have_tar_header_field(:typeflag, "5")
    end

    it "encodes typeflag for symlinks" do
      header =
        described_class.new(
          name: "link.txt",
          linkname: "target.txt",
          typeflag: MiniTarball::Header::TYPE_SYMLINK,
        )
      binary = header.to_binary
      expect(binary).to have_tar_header_field(:typeflag, "2")
      expect(binary).to have_tar_header_field(:linkname, "target.txt")
    end
  end

  describe "#has_long_linkname?" do
    it "returns false for link targets at exactly 100 bytes" do
      header = described_class.new(name: "link", linkname: "a" * 100)
      expect(header.has_long_linkname?).to be false
    end

    it "returns true for link targets over 100 bytes" do
      header = described_class.new(name: "link", linkname: "a" * 101)
      expect(header.has_long_linkname?).to be true
    end

    it "returns false for short link targets" do
      header = described_class.new(name: "link", linkname: "target.txt")
      expect(header.has_long_linkname?).to be false
    end

    it "counts bytes not characters for multibyte targets" do
      # 34 chars × 3 bytes = 102 bytes
      header = described_class.new(name: "link", linkname: "日" * 34)
      expect(header.has_long_linkname?).to be true
    end
  end

  describe ".long_link_header" do
    it "creates a header for long filename entries" do
      header = described_class.long_link_header("a" * 200)

      expect(header.value_of(:name)).to eq("././@LongLink")
      expect(header.value_of(:typeflag)).to eq("L")
      expect(header.value_of(:size)).to eq(201) # name length + 1 for null terminator
    end
  end

  describe ".long_linkname_header" do
    it "creates a header for long link target entries" do
      header = described_class.long_linkname_header("a" * 200)

      expect(header.value_of(:name)).to eq("././@LongLink")
      expect(header.value_of(:typeflag)).to eq("K")
      expect(header.value_of(:size)).to eq(201) # target length + 1 for null terminator
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
end
