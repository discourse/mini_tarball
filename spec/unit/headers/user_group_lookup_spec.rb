# frozen_string_literal: true

RSpec.describe MiniTarball::UserGroupLookup do
  describe ".username" do
    it "returns username for uid" do
      passwd = instance_double(Etc::Passwd, name: "alice")
      allow(Etc).to receive(:getpwuid).with(1000).and_return(passwd)

      expect(described_class.username(1000)).to eq("alice")
    end

    it "returns default when uid lookup fails" do
      allow(Etc).to receive(:getpwuid).and_raise(ArgumentError)

      expect(described_class.username(12_345)).to eq("nobody")
    end
  end

  describe ".groupname" do
    it "returns groupname for gid" do
      group = instance_double(Etc::Group, name: "staff")
      allow(Etc).to receive(:getgrgid).with(500).and_return(group)

      expect(described_class.groupname(500)).to eq("staff")
    end

    it "returns default when gid lookup fails" do
      allow(Etc).to receive(:getgrgid).and_raise(ArgumentError)

      expect(described_class.groupname(12_345)).to eq("nogroup")
    end
  end
end
