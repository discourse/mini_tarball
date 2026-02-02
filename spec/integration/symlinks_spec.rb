# frozen_string_literal: true

require_relative "../integration_helper"

RSpec.describe "Symlinks" do
  it "extracts a symlink with short target" do
    build_archive do
      file "target.txt", content: "target content"
      symlink "link.txt", target: "target.txt"
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, "link.txt")).to be_symlink(target: "target.txt")
    end
  end

  it "extracts a symlink with relative path" do
    build_archive do
      file "subdir/target.txt", content: "content"
      symlink "link.txt", target: "subdir/target.txt"
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, "link.txt")).to be_symlink(target: "subdir/target.txt")
    end
  end

  it "extracts a symlink with long target (>100 bytes, GNU extension)" do
    long_dir = "a" * 50
    long_file = "b" * 50
    target = "#{long_dir}/#{long_file}.txt"

    build_archive do
      file target, content: "content"
      symlink "link.txt", target:
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, "link.txt")).to be_symlink(target:)
    end
  end

  it "extracts a symlink with long name and long target" do
    long_link_name = "links/" + ("l" * 110) + ".txt"
    long_target = "targets/" + ("t" * 110) + ".txt"

    build_archive do
      file long_target, content: "content"
      symlink long_link_name, target: long_target
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, long_link_name)).to be_symlink(target: long_target)
      expect(File.join(dir, long_target)).to be_file(content: "content")
    end
  end
end
