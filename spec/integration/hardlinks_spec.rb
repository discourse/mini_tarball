# frozen_string_literal: true

require_relative "../integration_helper"

RSpec.describe "Hardlinks" do
  it "extracts a basic hardlink" do
    build_archive do
      file "original.txt", content: "shared content"
      hardlink "link.txt", target: "original.txt"
    end.with_extraction do |dir, success|
      expect(success).to be true
      original = File.join(dir, "original.txt")
      link = File.join(dir, "link.txt")

      expect(link).to be_hardlink_of(original)
      expect(File.read(link)).to eq("shared content")
    end
  end

  it "extracts a hardlink with long target (>100 bytes)" do
    long_dir = "a" * 50
    long_file = "b" * 50
    target = "#{long_dir}/#{long_file}.txt"

    build_archive do
      directory long_dir
      file target, content: "content"
      hardlink "link.txt", target:
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, "link.txt")).to be_hardlink_of(File.join(dir, target))
    end
  end
end
