# frozen_string_literal: true

RSpec.describe MiniTarball::Entry do
  def build_entry(overrides = {})
    defaults = {
      name: "test.txt",
      size: 100,
      mode: 0644,
      uid: 1000,
      gid: 1000,
      mtime: 1_700_000_000,
      uname: "user",
      gname: "group",
      typeflag: "0",
      linkname: "",
    }
    described_class.new(defaults.merge(overrides))
  end

  describe "#initialize" do
    it "sets all attributes from header values" do
      entry = build_entry

      expect(entry.name).to eq("test.txt")
      expect(entry.size).to eq(100)
      expect(entry.mode).to eq(0644)
      expect(entry.uid).to eq(1000)
      expect(entry.gid).to eq(1000)
      expect(entry.uname).to eq("user")
      expect(entry.gname).to eq("group")
      expect(entry.typeflag).to eq("0")
      expect(entry.linkname).to eq("")
    end

    it "converts mtime to Time object" do
      entry = build_entry(mtime: 1_700_000_000)
      expect(entry.mtime).to be_a(Time)
      expect(entry.mtime.to_i).to eq(1_700_000_000)
    end

    it "handles nil mtime" do
      entry = build_entry(mtime: nil)
      expect(entry.mtime).to be_nil
    end
  end

  describe "#file?" do
    it "returns true for typeflag '0'" do
      expect(build_entry(typeflag: "0").file?).to be true
    end

    it "returns true for empty typeflag" do
      expect(build_entry(typeflag: "").file?).to be true
    end

    it "returns true for nil typeflag" do
      expect(build_entry(typeflag: nil).file?).to be true
    end

    it "returns false for directory" do
      expect(build_entry(typeflag: "5").file?).to be false
    end
  end

  describe "#directory?" do
    it "returns true for typeflag '5'" do
      expect(build_entry(typeflag: "5").directory?).to be true
    end

    it "returns false for regular file" do
      expect(build_entry(typeflag: "0").directory?).to be false
    end
  end

  describe "#symlink?" do
    it "returns true for typeflag '2'" do
      expect(build_entry(typeflag: "2").symlink?).to be true
    end

    it "returns false for regular file" do
      expect(build_entry(typeflag: "0").symlink?).to be false
    end
  end

  describe "#hardlink?" do
    it "returns true for typeflag '1'" do
      expect(build_entry(typeflag: "1").hardlink?).to be true
    end

    it "returns false for regular file" do
      expect(build_entry(typeflag: "0").hardlink?).to be false
    end
  end
end
