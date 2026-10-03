# frozen_string_literal: true

RSpec.describe MiniTarball::UserGroupLookup do
  describe ".username" do
    it "returns username for uid" do
      passwd = instance_double(Etc::Passwd, name: "alice")
      allow(Etc).to receive(:getpwuid).with(1000).and_return(passwd)

      expect(described_class.username(1000)).to eq("alice")
    end

    it "returns an empty name when uid lookup fails" do
      allow(Etc).to receive(:getpwuid).and_raise(ArgumentError)

      expect(described_class.username(12_345)).to eq("")
    end

    it "returns an empty name for a uid that is too large for the system lookup" do
      expect(described_class.username(5_000_000_000)).to eq("")
    end

    it "returns an empty name when the system name doesn't fit the header field" do
      allow(Etc).to receive(:getpwuid).and_return(instance_double(Etc::Passwd, name: "u" * 33))

      expect(described_class.username(1000)).to eq("")
    end

    it "returns an empty name when the platform returns nil for the uid" do
      allow(Etc).to receive(:getpwuid).and_return(nil)

      expect(described_class.username(12_345)).to eq("")
    end
  end

  describe ".groupname with a platform returning nil" do
    it "returns an empty name" do
      allow(Etc).to receive(:getgrgid).and_return(nil)

      expect(described_class.groupname(12_345)).to eq("")
    end
  end

  describe ".groupname" do
    it "returns groupname for gid" do
      group = instance_double(Etc::Group, name: "staff")
      allow(Etc).to receive(:getgrgid).with(500).and_return(group)

      expect(described_class.groupname(500)).to eq("staff")
    end

    it "returns an empty name when gid lookup fails" do
      allow(Etc).to receive(:getgrgid).and_raise(ArgumentError)

      expect(described_class.groupname(12_345)).to eq("")
    end

    it "returns an empty name for a gid that is too large for the system lookup" do
      expect(described_class.groupname(5_000_000_000)).to eq("")
    end
  end

  describe MiniTarball::UserGroupLookup::Cache do
    subject(:cache) { described_class.new }

    it "looks up each uid only once" do
      passwd = instance_double(Etc::Passwd, name: "alice")
      allow(Etc).to receive(:getpwuid).with(1000).and_return(passwd)

      2.times { expect(cache.username(1000)).to eq("alice") }

      expect(Etc).to have_received(:getpwuid).once
    end

    it "looks up each gid only once" do
      group = instance_double(Etc::Group, name: "staff")
      allow(Etc).to receive(:getgrgid).with(500).and_return(group)

      2.times { expect(cache.groupname(500)).to eq("staff") }

      expect(Etc).to have_received(:getgrgid).once
    end

    it "caches the empty name for unknown uids" do
      allow(Etc).to receive(:getpwuid).and_raise(ArgumentError)

      2.times { expect(cache.username(12_345)).to eq("") }

      expect(Etc).to have_received(:getpwuid).once
    end

    it "caches the empty name for unknown gids" do
      allow(Etc).to receive(:getgrgid).and_raise(ArgumentError)

      2.times { expect(cache.groupname(12_345)).to eq("") }

      expect(Etc).to have_received(:getgrgid).once
    end

    it "does not share entries between instances" do
      allow(Etc).to receive(:getpwuid).and_return(instance_double(Etc::Passwd, name: "alice"))

      described_class.new.username(1000)
      described_class.new.username(1000)

      expect(Etc).to have_received(:getpwuid).twice
    end
  end

  it "returns an empty group name when the system name doesn't fit the header field" do
    allow(Etc).to receive(:getgrgid).and_return(instance_double(Etc::Group, name: "g" * 33))

    expect(described_class.groupname(1000)).to eq("")
  end
end
