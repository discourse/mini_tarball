# frozen_string_literal: true

RSpec.describe MiniTarball::UserGroupLookup do
  describe ".username" do
    it "returns username for valid uid" do
      # Use current user's uid which should always exist
      current_uid = Process.uid
      result = described_class.username(current_uid)

      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it "returns default for invalid uid" do
      # Use an unlikely uid that probably doesn't exist
      result = described_class.username(99_999)

      expect(result).to eq("nobody")
    end
  end

  describe ".groupname" do
    it "returns groupname for valid gid" do
      # Use current user's gid which should always exist
      current_gid = Process.gid
      result = described_class.groupname(current_gid)

      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it "returns default for invalid gid" do
      # Use an unlikely gid that probably doesn't exist
      result = described_class.groupname(99_999)

      expect(result).to eq("nogroup")
    end
  end
end
