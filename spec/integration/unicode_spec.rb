# frozen_string_literal: true

require_relative "../integration_helper"

RSpec.describe "Unicode" do
  it "extracts a file with UTF-8 filename" do
    build_archive { file "日本語ファイル.txt", content: "Japanese filename" }.with_extraction do |dir|
      expect(File.join(dir, "日本語ファイル.txt")).to be_file(content: "Japanese filename")
    end
  end

  it "extracts a file with emoji in filename" do
    build_archive { file "emoji_🎉_test.txt", content: "party!" }.with_extraction do |dir|
      expect(File.join(dir, "emoji_🎉_test.txt")).to be_file(content: "party!")
    end
  end

  it "extracts a directory with UTF-8 name" do
    build_archive { directory "каталог" }.with_extraction do |dir|
      expect(File.join(dir, "каталог")).to be_dir
    end
  end

  it "extracts a symlink with UTF-8 target" do
    build_archive do
      file "目標.txt", content: "target"
      symlink "リンク.txt", target: "目標.txt"
    end.with_extraction { |dir| expect(File.join(dir, "リンク.txt")).to be_symlink(target: "目標.txt") }
  end
end
