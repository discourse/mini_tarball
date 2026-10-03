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
      expect(header.to_binary).to have_tar_header_field(:magic, "ustar ")
    end

    it "produces a valid checksum" do
      binary = described_class.new(name: "test.txt", size: 1024).to_binary
      field = TarHeaderFormat.field(:checksum)

      # Tar checksum = sum of all bytes, with checksum field treated as 8 spaces
      header_with_blank_checksum = binary.dup
      header_with_blank_checksum[field["offset"], field["length"]] = " " * 8
      expected = header_with_blank_checksum.bytes.sum

      expect(binary).to have_tar_header_field(:checksum, expected)
    end

    it "encodes mode as octal" do
      attrs =
        MiniTarball::EntryAttributes.new(
          mode: 0755,
          uid: nil,
          gid: nil,
          uname: nil,
          gname: nil,
          mtime: nil,
        )
      header = described_class.new(name: "test.txt", attrs:)
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

    it "encodes uid and gid" do
      attrs =
        MiniTarball::EntryAttributes.new(
          mode: 0644,
          uid: 1000,
          gid: 500,
          uname: nil,
          gname: nil,
          mtime: nil,
        )
      binary = described_class.new(name: "test.txt", attrs:).to_binary
      expect(binary).to have_tar_header_field(:uid, 1000)
      expect(binary).to have_tar_header_field(:gid, 500)
    end

    it "encodes uname and gname" do
      attrs =
        MiniTarball::EntryAttributes.new(
          mode: 0644,
          uid: nil,
          gid: nil,
          uname: "alice",
          gname: "staff",
          mtime: nil,
        )
      binary = described_class.new(name: "test.txt", attrs:).to_binary
      expect(binary).to have_tar_header_field(:uname, "alice")
      expect(binary).to have_tar_header_field(:gname, "staff")
    end

    it "encodes mtime as unix timestamp" do
      mtime = Time.utc(2024, 6, 15, 12, 0, 0)
      attrs =
        MiniTarball::EntryAttributes.new(
          mode: 0644,
          uid: nil,
          gid: nil,
          uname: nil,
          gname: nil,
          mtime:,
        )
      binary = described_class.new(name: "test.txt", attrs:).to_binary
      expect(binary).to have_tar_header_field(:mtime, mtime.to_i)
    end

    describe "mtime" do
      def mtime_bytes(mtime)
        attrs = MiniTarball::EntryAttributes.with_file_defaults(mtime:)
        described_class.new(name: "test.txt", attrs:).to_binary.byteslice(136, 12)
      end

      it "encodes an Integer mtime" do
        expect(mtime_bytes(1_613_347_200)).to eq("14012334600\0")
      end

      it "encodes an mtime before 1970 as base-256" do
        expect(mtime_bytes(Time.at(-1).utc)).to eq(("\xFF" * 12).b)
        expect(mtime_bytes(Time.utc(1969, 12, 31))).to eq("#{"\xFF" * 9}\xFE\xAE\x80".b)
      end

      it "uses whole seconds for an mtime with fractions" do
        expect(mtime_bytes(Time.at(1, 500_000, :usec))).to eq("00000000001\0")
      end
    end

    it "encodes version" do
      binary = described_class.new(name: "test.txt").to_binary
      expect(binary).to have_tar_header_field(:version, " ")
    end

    it "leaves devmajor and devminor empty" do
      binary = described_class.new(name: "test.txt").to_binary
      expect(binary).to have_tar_header_field(:devmajor, "")
      expect(binary).to have_tar_header_field(:devminor, "")
    end

    it "leaves prefix empty" do
      binary = described_class.new(name: "test.txt").to_binary
      expect(binary).to have_tar_header_field(:prefix, "")
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

  describe "without attributes" do
    let(:binary) { described_class.new(name: "test.txt").to_binary }

    it "uses mode 0 and size 0" do
      expect(binary).to have_tar_header_field(:mode, "0000000")
      expect(binary).to have_tar_header_field(:size, "00000000000")
    end

    it "uses the current time as mtime" do
      mtime = Integer(binary.byteslice(136, 11), 8)
      expect(mtime).to be_within(5).of(Time.now.to_i)
    end
  end

  describe "checksum" do
    it "isn't cut off for headers whose bytes add up to more than 16 bits" do
      name = "\xFF".b * 100
      owner = "\xFF".b * 32
      attrs = MiniTarball::EntryAttributes.with_file_defaults(uname: owner, gname: owner)
      binary = described_class.new(name:, linkname: "\xFF".b * 100, attrs:).to_binary

      expected = binary.dup
      expected[148, 8] = " " * 8
      expect(expected.sum(0)).to be > 0xFFFF
      expect(binary).to have_tar_header_field(:checksum, expected.sum(0))
    end
  end
end
