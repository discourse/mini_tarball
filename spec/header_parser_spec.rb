# frozen_string_literal: true

RSpec.describe MiniTarball::HeaderParser do
  def create_tar_with_file(content)
    io = StringIO.new.binmode
    MiniTarball::Writer.use(io) do |writer|
      writer.add_file_from_stream(
        name: "test.txt",
        mode: 0644,
        uname: "user",
        gname: "group",
      ) { |s| s.write(content) }
    end
    io.string
  end

  describe ".parse" do
    it "parses a valid header" do
      tar_data = create_tar_with_file("hello")
      header_data = tar_data[0, 512]

      values = described_class.parse(header_data)

      expect(values[:name]).to eq("test.txt")
      expect(values[:size]).to eq(5)
      expect(values[:mode]).to eq(0644)
      expect(values[:uname]).to eq("user")
      expect(values[:gname]).to eq("group")
      expect(values[:typeflag]).to eq("0")
    end

    it "returns nil for nil input" do
      expect(described_class.parse(nil)).to be_nil
    end

    it "raises InvalidHeaderError for truncated header" do
      expect { described_class.parse("short") }.to raise_error(
        MiniTarball::InvalidHeaderError,
        "Truncated header",
      )
    end

    it "raises InvalidHeaderError for header just under block size" do
      expect { described_class.parse("x" * 511) }.to raise_error(
        MiniTarball::InvalidHeaderError,
        "Truncated header",
      )
    end

    it "returns nil for end-of-archive marker" do
      expect(described_class.parse("\0" * 512)).to be_nil
    end

    it "raises ChecksumMismatchError for corrupted header" do
      tar_data = create_tar_with_file("hello")
      header_data = tar_data[0, 512]
      # Corrupt the header
      corrupted = header_data.dup
      corrupted[0] = "X"

      expect { described_class.parse(corrupted) }.to raise_error(MiniTarball::ChecksumMismatchError)
    end
  end

  describe ".end_of_archive?" do
    it "returns true for null block" do
      expect(described_class.end_of_archive?("\0" * 512)).to be true
    end

    it "returns false for non-null data" do
      expect(described_class.end_of_archive?("a" * 512)).to be false
    end
  end

  context "with base-256 encoded size" do
    # Size field is at offset 124 (100+8+8+8) and is 12 bytes long
    SIZE_FIELD_OFFSET = 124

    def create_header_with_base256_size(size_bytes)
      tar_data = create_tar_with_file("hello")
      header_data = tar_data[0, 512].dup.force_encoding(Encoding::BINARY)
      header_data[SIZE_FIELD_OFFSET, 12] = size_bytes
      recalculate_checksum(header_data)
    end

    def recalculate_checksum(header_data)
      checksum_offset = 148
      header_data[checksum_offset, 8] = " " * 8
      checksum = header_data.bytes.sum
      header_data[checksum_offset, 8] = format("%06o\0 ", checksum)
      header_data
    end

    it "parses large file sizes correctly" do
      io = StringIO.new.binmode
      MiniTarball::Writer.use(io) do |writer|
        writer.add_file_from_stream(name: "big.txt", size: 8_589_934_592) do |s|
          # Don't actually write 8GB, just test the header
        end
      end

      header_data = io.string[0, 512]
      values = described_class.parse(header_data)

      expect(values[:size]).to eq(8_589_934_592)
    end

    it "raises InvalidHeaderError for negative base-256 size" do
      # Negative base-256: bit 7 (marker) and bit 6 (sign) both set = 0xC0+
      # This represents -1 in base-256 (all 0xFF after the marker)
      negative_size = (+"\xFF" * 12).force_encoding(Encoding::BINARY)
      header_data = create_header_with_base256_size(negative_size)

      expect { described_class.parse(header_data) }.to raise_error(
        MiniTarball::InvalidHeaderError,
        "Negative base-256 values not supported",
      )
    end

    it "parses positive base-256 values with high values correctly" do
      # Positive base-256: bit 7 set, bit 6 clear = 0x80
      # This encodes the value 1000 (0x3E8) in base-256
      positive_size = [0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x03, 0xE8].pack("C*")
      header_data = create_header_with_base256_size(positive_size)
      values = described_class.parse(header_data)

      expect(values[:size]).to eq(1000)
    end
  end
end
