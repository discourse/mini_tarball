# frozen_string_literal: true

require_relative "../integration_helper"

RSpec.describe "Mixed archives" do
  it "extracts an archive with all entry types" do
    build_archive do
      directory "project"
      directory "project/src"
      directory "project/data"

      file "project/README.md", content: "# Project\n\nA test project."
      file "project/src/main.rb", content: "puts 'Hello!'", mode: 0o755
      file "project/data/config.json", content: '{"key": "value"}'

      symlink "project/link_to_readme", target: "README.md"
      hardlink "project/readme_copy", target: "project/README.md"
    end.with_extraction do |dir, success|
      expect(success).to be true

      # Directories
      expect(File.join(dir, "project")).to be_dir
      expect(File.join(dir, "project/src")).to be_dir
      expect(File.join(dir, "project/data")).to be_dir

      # Files
      expect(File.join(dir, "project/README.md")).to be_file(
        content: "# Project\n\nA test project.",
      )
      expect(File.join(dir, "project/src/main.rb")).to be_file(content: "puts 'Hello!'")
      expect(File.stat(File.join(dir, "project/src/main.rb")).mode & 0o777).to eq(0o755)

      # Symlink
      expect(File.symlink?(File.join(dir, "project/link_to_readme"))).to be true
      expect(File.readlink(File.join(dir, "project/link_to_readme"))).to eq("README.md")

      # Hardlink
      expect(File.join(dir, "project/readme_copy")).to be_hardlink_of(
        File.join(dir, "project/README.md"),
      )
    end
  end

  it "extracts an archive with long names and unicode" do
    long_dir = "long_" + "x" * 100
    unicode_file = "файл_データ.txt"

    build_archive do
      file "#{long_dir}/#{unicode_file}", content: "mixed content"
      symlink "link", target: "#{long_dir}/#{unicode_file}"
    end.with_extraction do |dir, success|
      expect(success).to be true
      expect(File.join(dir, long_dir, unicode_file)).to be_file(content: "mixed content")
      expect(File.readlink(File.join(dir, "link"))).to eq("#{long_dir}/#{unicode_file}")
    end
  end

  it "extracts multiple hardlinks to the same file" do
    build_archive do
      file "original.txt", content: "shared"
      hardlink "link1.txt", target: "original.txt"
      hardlink "link2.txt", target: "original.txt"
      hardlink "link3.txt", target: "original.txt"
    end.with_extraction do |dir, success|
      expect(success).to be true
      original = File.join(dir, "original.txt")

      expect(File.join(dir, "link1.txt")).to be_hardlink_of(original)
      expect(File.join(dir, "link2.txt")).to be_hardlink_of(original)
      expect(File.join(dir, "link3.txt")).to be_hardlink_of(original)
    end
  end
end
