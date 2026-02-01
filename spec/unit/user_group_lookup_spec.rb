# frozen_string_literal: true

RSpec.describe MiniTarball::UserGroupLookup do
  describe ".username" do
    it "returns username for valid uid or falls back to default" do
      # Use current user's uid - may not have passwd entry in minimal containers
      current_uid = Process.uid
      result = described_class.username(current_uid)

      expect(result).to be_a(String)
      expect(result).not_to be_empty
      # Result is either the actual username or "nobody" fallback
    end

    it "returns default when uid lookup fails" do
      allow(Etc).to receive(:getpwuid).and_raise(ArgumentError)

      result = described_class.username(12_345)

      expect(result).to eq("nobody")
    end
  end

  describe ".groupname" do
    it "returns groupname for valid gid or falls back to default" do
      # Use current user's gid - may not have group entry in minimal containers
      current_gid = Process.gid
      result = described_class.groupname(current_gid)

      expect(result).to be_a(String)
      expect(result).not_to be_empty
      # Result is either the actual groupname or "nogroup" fallback
    end

    it "returns default when gid lookup fails" do
      allow(Etc).to receive(:getgrgid).and_raise(ArgumentError)

      result = described_class.groupname(12_345)

      expect(result).to eq("nogroup")
    end
  end
end
