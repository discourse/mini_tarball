# frozen_string_literal: true

require_relative "../integration_helper"

RSpec.describe "Symlinks" do
  it "extracts a symlink with short target" do
    build_archive do
      file "target.txt", content: "target content"
      symlink "link.txt", target: "target.txt"
    end.with_extraction do |dir, success|
      expect(success).to be true
      link_path = File.join(dir, "link.txt")
      expect(File.symlink?(link_path)).to be true
      expect(File.readlink(link_path)).to eq("target.txt")
    end
  end

  it "extracts a symlink with relative path" do
    build_archive do
      directory "subdir"
      file "subdir/target.txt", content: "content"
      symlink "link.txt", target: "subdir/target.txt"
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.readlink(File.join(dir, "link.txt"))).to eq("subdir/target.txt")
    end
  end

  it "extracts a symlink with long target (>100 bytes, GNU extension)" do
    long_dir = "a" * 50
    long_file = "b" * 50
    target = "#{long_dir}/#{long_file}.txt"

    build_archive do
      directory long_dir
      file target, content: "content"
      symlink "link.txt", target:
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.readlink(File.join(dir, "link.txt"))).to eq(target)
    end
  end
end
