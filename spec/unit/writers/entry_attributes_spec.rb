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

    it "looks up names for overridden IDs instead of the file owner's IDs" do
      allow(MiniTarball::UserGroupLookup).to receive(:username).with(0).and_return("root")
      allow(MiniTarball::UserGroupLookup).to receive(:groupname).with(0).and_return("wheel")

      attrs = described_class.from_stat(stat, uid: 0, gid: 0)

      expect(attrs.uid).to eq(0)
      expect(attrs.uname).to eq("root")
      expect(attrs.gid).to eq(0)
      expect(attrs.gname).to eq("wheel")
    end

    it "uses the given lookup to resolve names" do
      lookup = instance_double(MiniTarball::UserGroupLookup::Cache)
      allow(lookup).to receive(:username).with(1000).and_return("cached-user")
      allow(lookup).to receive(:groupname).with(1000).and_return("cached-group")

      attrs = described_class.from_stat(stat, lookup:)

      expect(attrs.uname).to eq("cached-user")
      expect(attrs.gname).to eq("cached-group")
    end
  end

  describe ".with_defaults" do
    it "replaces nil values with defaults" do
      attrs = described_class.with_defaults(default_mode: 0755, mode: nil, uname: nil, gname: nil)

      expect(attrs.mode).to eq(0755)
      expect(attrs.uname).to eq("nobody")
      expect(attrs.gname).to eq("nogroup")
    end

    it "keeps given values" do
      attrs = described_class.with_defaults(default_mode: 0755, mode: 0700, uname: "alice")

      expect(attrs.mode).to eq(0700)
      expect(attrs.uname).to eq("alice")
    end
  end

  describe "numeric attributes" do
    def build(**overrides)
      described_class.new(
        mode: 0644,
        uid: 1000,
        gid: 1000,
        uname: "alice",
        gname: "staff",
        mtime: nil,
        **overrides,
      )
    end

    it "accepts zero, large values and nil" do
      expect(build(mode: 0, uid: 0, gid: 0)).to have_attributes(mode: 0, uid: 0, gid: 0)
      expect(build(uid: 2**40, gid: 2**40)).to have_attributes(uid: 2**40, gid: 2**40)
      expect(build(mode: nil, uid: nil, gid: nil)).to have_attributes(mode: nil, uid: nil, gid: nil)
    end

    %i[mode uid gid].each do |name|
      it "rejects a negative #{name}" do
        expect { build(name => -1) }.to raise_error(
          ArgumentError,
          "#{name} must be a non-negative Integer: -1",
        )
      end

      it "rejects a #{name} that isn't an Integer" do
        expect { build(name => "1000") }.to raise_error(
          ArgumentError,
          "#{name} must be a non-negative Integer: \"1000\"",
        )
        expect { build(name => 1000.0) }.to raise_error(ArgumentError, /#{name} must be/)
      end
    end

    describe "with .from_stat" do
      let(:stat) do
        instance_double(File::Stat, mode: 0o100644, uid: 1000, gid: 1000, mtime: Time.at(0))
      end
      let(:lookup) do
        instance_double(MiniTarball::UserGroupLookup::Cache, username: "", groupname: "")
      end

      it "rejects a wrong uid before looking up any name" do
        expect { described_class.from_stat(stat, lookup:, uid: "1000") }.to raise_error(
          ArgumentError,
          "uid must be a non-negative Integer: \"1000\"",
        )
        expect(lookup).not_to have_received(:username)
      end

      it "rejects a wrong gid before looking up any name" do
        expect { described_class.from_stat(stat, lookup:, gid: -5) }.to raise_error(
          ArgumentError,
          "gid must be a non-negative Integer: -5",
        )
        expect(lookup).not_to have_received(:username)
        expect(lookup).not_to have_received(:groupname)
      end
    end
  end

  describe "mtime" do
    def build(mtime)
      described_class.new(mode: 0644, uid: nil, gid: nil, uname: nil, gname: nil, mtime:)
    end

    it "accepts nil, a Time and an Integer" do
      expect(build(nil).mtime).to be_nil
      expect(build(Time.utc(2021, 2, 15)).mtime).to eq(Time.utc(2021, 2, 15))
      expect(build(1_613_347_200).mtime).to eq(1_613_347_200)
    end

    it "accepts times before 1970" do
      expect(build(Time.at(-1)).mtime).to eq(Time.at(-1))
      expect(build(-86_400).mtime).to eq(-86_400)
    end

    it "rejects other values" do
      expect { build("123") }.to raise_error(
        ArgumentError,
        "mtime must be a Time or an Integer: \"123\"",
      )
      expect { build("2021-02-15") }.to raise_error(
        ArgumentError,
        "mtime must be a Time or an Integer: \"2021-02-15\"",
      )
      expect { build(1.5) }.to raise_error(ArgumentError, "mtime must be a Time or an Integer: 1.5")
      expect { build(false) }.to raise_error(ArgumentError, /mtime must be/)
    end

    it "checks the mtime given to .from_stat" do
      stat = instance_double(File::Stat, mode: 0o100644, uid: 0, gid: 0, mtime: Time.at(0))
      lookup = instance_double(MiniTarball::UserGroupLookup::Cache, username: "", groupname: "")

      expect { described_class.from_stat(stat, lookup:, mtime: "123") }.to raise_error(
        ArgumentError,
        /mtime must be/,
      )
    end

    it "checks the mtime given to .with_defaults" do
      expect { described_class.with_defaults(default_mode: 0644, mtime: "123") }.to raise_error(
        ArgumentError,
        /mtime must be/,
      )
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
