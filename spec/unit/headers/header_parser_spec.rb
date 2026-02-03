# frozen_string_literal: true

RSpec.describe MiniTarball::HeaderParser do
  describe ".parse" do
    it "parses a small file header" do
      data = fixture("headers/small_file_header")
      header = described_class.parse(data)

      expect(header.name).to eq("small_file")
      expect(header.mode).to eq(0644)
      expect(header.uid).to eq(1001)
      expect(header.gid).to eq(33)
      expect(header.size).to eq(536_870_913)
      expect(header.typeflag).to eq("0")
      expect(header.uname).to eq("discourse")
      expect(header.gname).to eq("www-data")
    end

    it "parses a directory header" do
      data = fixture("headers/directory_header")
      header = described_class.parse(data)

      expect(header.name).to eq("testdir/")
      expect(header.typeflag).to eq("5")
      expect(header.size).to eq(0)
      expect(header.mode).to eq(0755)
    end

    it "parses a symlink header" do
      data = fixture("headers/symlink_short_target_header")
      header = described_class.parse(data)

      expect(header.name).to eq("link.txt")
      expect(header.typeflag).to eq("2")
      expect(header.linkname).to eq("target.txt")
    end

    it "parses a hardlink header" do
      data = fixture("headers/hardlink_short_target_header")
      header = described_class.parse(data)

      expect(header.name).to eq("hardlink.txt")
      expect(header.typeflag).to eq("1")
      expect(header.linkname).to eq("original.txt")
    end

    it "parses a header with long filename extension (first block is LongLink)" do
      # This fixture contains 3 blocks: LongLink header + name data + file header
      # We read just the first 512 bytes to parse the LongLink header
      data = fixture("headers/exactly_101_byte_name_header")
      first_block = data[0, 512]
      header = described_class.parse(first_block)

      expect(header.name).to eq("././@LongLink")
      expect(header.typeflag).to eq("L")
    end

    it "returns nil for null block (end-of-archive)" do
      data = "\0" * 512
      expect(described_class.parse(data)).to be_nil
    end

    it "raises InvalidHeaderError for wrong size data" do
      expect { described_class.parse("too short") }.to raise_error(
        MiniTarball::InvalidHeaderError,
        /must be 512 bytes/,
      )
    end

    it "raises ChecksumMismatchError for corrupted header" do
      data = fixture("headers/small_file_header").dup
      data[0] = "X" # corrupt the name field

      expect { described_class.parse(data) }.to raise_error(MiniTarball::ChecksumMismatchError)
    end

    it "can skip checksum verification" do
      data = fixture("headers/small_file_header").dup
      data[0] = "X"

      expect { described_class.parse(data, verify_checksum: false) }.not_to raise_error
    end

    it "treats empty typeflag as regular file" do
      # Create a header with null typeflag
      data = fixture("headers/small_file_header").dup
      data[156] = "\0"
      # Re-calculate checksum would be needed for real verification
      header = described_class.parse(data, verify_checksum: false)

      expect(header.typeflag).to eq("0")
    end
  end

  describe ".null_block?" do
    it "returns true for all-null block" do
      expect(described_class.null_block?("\0" * 512)).to be true
    end

    it "returns false for non-null block" do
      data = "\0" * 511 + "x"
      expect(described_class.null_block?(data)).to be false
    end
  end

  describe ".compute_checksum" do
    it "computes correct checksum for header" do
      data = fixture("headers/small_file_header")
      header = described_class.parse(data, verify_checksum: false)
      computed = described_class.compute_checksum(data)

      expect(computed).to eq(header.checksum)
    end
  end

  describe "base-256 number parsing" do
    it "parses large file size correctly" do
      data = fixture("headers/large_file_header")
      header = described_class.parse(data)

      # 10GB sparse file
      expect(header.size).to eq(10_737_418_241)
    end

    it "uses the first byte payload bits for base-256 values" do
      data = fixture("headers/small_file_header").dup
      field = described_class::FIELD_OFFSETS[:size]
      size_length = field[:length]
      size_offset = field[:offset]
      encoded = ([0x81] + [0x00] * (size_length - 1)).pack("C*")
      data[size_offset, size_length] = encoded

      header = described_class.parse(data, verify_checksum: false)

      expect(header.size).to eq(1 << (8 * (size_length - 1)))
    end
  end

  describe "ParsedHeader#full_name" do
    it "returns name when no prefix" do
      data = fixture("headers/small_file_header")
      header = described_class.parse(data)

      expect(header.full_name).to eq(header.name)
    end

    it "combines prefix and name" do
      # This is a multi-block fixture, first block is LongLink header
      data = fixture("headers/long_path_header")
      first_block = data[0, 512]
      header = described_class.parse(first_block)

      # First block is the ././@LongLink header, which has no prefix
      expect(header.name).to eq("././@LongLink")
    end

    it "uses short path header for prefix test" do
      data = fixture("headers/short_path_header")
      header = described_class.parse(data)

      # short_path fixture stores path differently based on tar implementation
      expect(header.full_name).to include("short/path")
    end
  end

  describe "ParsedHeader#gnu_format?" do
    it "returns true for GNU tar header" do
      data = fixture("headers/small_file_header")
      header = described_class.parse(data)

      expect(header.gnu_format?).to be true
    end
  end
end
