# frozen_string_literal: true

require_relative "../integration_helper"

RSpec.describe "Unicode" do
  it "extracts a file with UTF-8 filename" do
    build_archive do
      file "日本語ファイル.txt", content: "Japanese filename"
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, "日本語ファイル.txt")).to be_file(content: "Japanese filename")
    end
  end

  it "extracts a file with emoji in filename" do
    build_archive { file "emoji_🎉_test.txt", content: "party!" }.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, "emoji_🎉_test.txt")).to be_file(content: "party!")
    end
  end

  it "extracts a directory with UTF-8 name" do
    build_archive do
      directory "каталог"
      file "каталог/файл.txt", content: "Cyrillic"
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, "каталог")).to be_dir
      expect(File.join(dir, "каталог/файл.txt")).to be_file(content: "Cyrillic")
    end
  end

  it "extracts a symlink with UTF-8 target" do
    build_archive do
      file "目標.txt", content: "target"
      symlink "リンク.txt", target: "目標.txt"
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.readlink(File.join(dir, "リンク.txt"))).to eq("目標.txt")
    end
  end
end
