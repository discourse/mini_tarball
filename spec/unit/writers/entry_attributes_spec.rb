# frozen_string_literal: true

RSpec.describe MiniTarball::EntryAttributes do
  describe ".from_stat" do
    let(:stat) do
      instance_double(
        File::Stat,
        mode: 0o100644,
        uid: 1000,
        gid: 1000,
        mtime: Time.utc(2021, 6, 15),
      )
    end

    before do
      allow(MiniTarball::UserGroupLookup).to receive(:username).with(1000).and_return("testuser")
      allow(MiniTarball::UserGroupLookup).to receive(:groupname).with(1000).and_return("testgroup")
    end

    it "extracts values from stat" do
      attrs = described_class.from_stat(stat)

      expect(attrs.mode).to eq(0o100644)
      expect(attrs.uid).to eq(1000)
      expect(attrs.gid).to eq(1000)
      expect(attrs.uname).to eq("testuser")
      expect(attrs.gname).to eq("testgroup")
      expect(attrs.mtime).to eq(Time.utc(2021, 6, 15))
    end

    it "allows overriding individual values" do
      attrs = described_class.from_stat(stat, mode: 0755, uname: "override")

      expect(attrs.mode).to eq(0755)
      expect(attrs.uname).to eq("override")
      expect(attrs.uid).to eq(1000) # from stat
      expect(attrs.gname).to eq("testgroup") # from stat
    end

    it "allows overriding all values" do
      custom_time = Time.utc(2025, 1, 1)
      attrs =
        described_class.from_stat(
          stat,
          mode: 0700,
          uid: 0,
          gid: 0,
          uname: "root",
          gname: "wheel",
          mtime: custom_time,
        )

      expect(attrs.mode).to eq(0700)
      expect(attrs.uid).to eq(0)
      expect(attrs.gid).to eq(0)
      expect(attrs.uname).to eq("root")
      expect(attrs.gname).to eq("wheel")
      expect(attrs.mtime).to eq(custom_time)
    end
  end

  describe "immutability" do
    it "is frozen" do
      attrs =
        described_class.new(
          mode: 0644,
          uid: nil,
          gid: nil,
          uname: "nobody",
          gname: "nogroup",
          mtime: nil,
        )
      expect(attrs).to be_frozen
    end
  end
end
