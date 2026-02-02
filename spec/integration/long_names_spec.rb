# frozen_string_literal: true

require_relative "../integration_helper"

RSpec.describe "Long names" do
  it "extracts a filename at exactly 100 bytes (boundary)" do
    name = "a" * 96 + ".txt" # exactly 100 bytes
    build_archive { file name, content: "content" }.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, name)).to be_file(content: "content")
    end
  end

  it "extracts a filename longer than 100 bytes (GNU extension)" do
    name = "a" * 100 + ".txt" # 104 bytes
    build_archive { file name, content: "content" }.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, name)).to be_file(content: "content")
    end
  end

  it "extracts a deeply nested path" do
    full_path = (1..10).map { |i| "dir#{i}" }.join("/") + "/file.txt"

    build_archive { file full_path, content: "deep content" }.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, full_path)).to be_file(content: "deep content")
    end
  end

  it "extracts a directory name longer than 100 bytes" do
    long_dir = "d" * 110
    build_archive do
      directory long_dir
      file "#{long_dir}/file.txt", content: "content"
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, long_dir)).to be_dir
      expect(File.join(dir, long_dir, "file.txt")).to be_file
    end
  end
end
