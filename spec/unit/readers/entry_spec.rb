# frozen_string_literal: true

require "time"

RSpec.describe MiniTarball::Entry do
  let(:regular_header) { MiniTarball::HeaderParser.parse(fixture("headers/small_file_header")) }

  let(:directory_header) { MiniTarball::HeaderParser.parse(fixture("headers/directory_header")) }

  let(:symlink_header) do
    MiniTarball::HeaderParser.parse(fixture("headers/symlink_short_target_header"))
  end

  let(:hardlink_header) do
    MiniTarball::HeaderParser.parse(fixture("headers/hardlink_short_target_header"))
  end

  describe ".from_header" do
    it "creates entry from parsed header" do
      entry = described_class.from_header(regular_header)

      expect(entry.name).to eq("small_file")
      expect(entry.mode).to eq(0644)
      expect(entry.uid).to eq(1001)
      expect(entry.gid).to eq(33)
      expect(entry.size).to eq(536_870_913)
      expect(entry.uname).to eq("discourse")
      expect(entry.gname).to eq("www-data")
    end

    it "converts mtime to Time" do
      entry = described_class.from_header(regular_header)

      expect(entry.mtime).to be_a(Time)
      expect(entry.mtime).to eq(Time.parse("2021-02-15T20:11:34Z"))
    end

    it "overrides header values with pax attributes" do
      pax_attrs = {
        "path" => "pax/override/path.txt",
        "uid" => "9999",
        "gid" => "8888",
        "size" => "12345",
        "uname" => "paxuser",
        "gname" => "paxgroup",
        "linkpath" => "pax/target",
      }

      entry = described_class.from_header(regular_header, pax_attributes: pax_attrs)

      expect(entry.name).to eq("pax/override/path.txt")
      expect(entry.uid).to eq(9999)
      expect(entry.gid).to eq(8888)
      expect(entry.size).to eq(12_345)
      expect(entry.uname).to eq("paxuser")
      expect(entry.gname).to eq("paxgroup")
      expect(entry.linkname).to eq("pax/target")
    end

    it "handles pax mtime with nanosecond precision" do
      pax_attrs = { "mtime" => "1613419894.123456789" }
      entry = described_class.from_header(regular_header, pax_attributes: pax_attrs)

      expect(entry.mtime.to_i).to eq(1_613_419_894)
      expect(entry.mtime.nsec).to eq(123_456_789)
    end
  end

  describe "#file?" do
    it "returns true for regular files" do
      entry = described_class.from_header(regular_header)
      expect(entry.file?).to be true
    end

    it "returns false for directories" do
      entry = described_class.from_header(directory_header)
      expect(entry.file?).to be false
    end

    it "returns false for symlinks" do
      entry = described_class.from_header(symlink_header)
      expect(entry.file?).to be false
    end
  end

  describe "#directory?" do
    it "returns true for directories" do
      entry = described_class.from_header(directory_header)
      expect(entry.directory?).to be true
    end

    it "returns false for regular files" do
      entry = described_class.from_header(regular_header)
      expect(entry.directory?).to be false
    end
  end

  describe "#symlink?" do
    it "returns true for symlinks" do
      entry = described_class.from_header(symlink_header)
      expect(entry.symlink?).to be true
    end

    it "returns false for regular files" do
      entry = described_class.from_header(regular_header)
      expect(entry.symlink?).to be false
    end
  end

  describe "#hardlink?" do
    it "returns true for hardlinks" do
      entry = described_class.from_header(hardlink_header)
      expect(entry.hardlink?).to be true
    end

    it "returns false for symlinks" do
      entry = described_class.from_header(symlink_header)
      expect(entry.hardlink?).to be false
    end
  end

  describe "#link?" do
    it "returns true for symlinks" do
      entry = described_class.from_header(symlink_header)
      expect(entry.link?).to be true
    end

    it "returns true for hardlinks" do
      entry = described_class.from_header(hardlink_header)
      expect(entry.link?).to be true
    end

    it "returns false for regular files" do
      entry = described_class.from_header(regular_header)
      expect(entry.link?).to be false
    end
  end

  describe "#metadata?" do
    it "returns false for regular files" do
      entry = described_class.from_header(regular_header)
      expect(entry.metadata?).to be false
    end

    it "returns true for pax extended headers" do
      long_link_data = fixture("headers/exactly_101_byte_name_header")[0, 512]
      long_link_header = MiniTarball::HeaderParser.parse(long_link_data)
      entry = described_class.from_header(long_link_header)

      # This is actually a GNU long link header (typeflag L)
      expect(entry.gnu_long_link?).to be true
      expect(entry.metadata?).to be true
    end
  end
end
