# frozen_string_literal: true

require_relative "../../integration_helper"

RSpec.describe "Mixed archives" do
  it "extracts an archive with all entry types" do
    build_archive do
      directory "project/empty"
      directory "project/restricted", mode: 0o700

      file "project/README.md", content: "# Project\n\nA test project."
      file "project/src/main.rb", content: "puts 'Hello!'", mode: 0o755

      symlink "link_to_readme", target: "project/README.md"
      hardlink "project/readme_copy", target: "project/README.md"
    end.with_extraction do |dir|
      expect(File.join(dir, "project/empty")).to be_dir
      expect(File.join(dir, "project/restricted")).to be_dir
      expect(File.join(dir, "project/restricted")).to have_mode(0o700)

      expect(File.join(dir, "project/README.md")).to be_file(
        content: "# Project\n\nA test project.",
      )
      expect(File.join(dir, "project/src/main.rb")).to be_file(content: "puts 'Hello!'")
      expect(File.join(dir, "project/src/main.rb")).to have_mode(0o755)

      expect(File.join(dir, "link_to_readme")).to be_symlink(target: "project/README.md")

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
    end.with_extraction do |dir|
      expect(File.join(dir, long_dir, unicode_file)).to be_file(content: "mixed content")
      expect(File.join(dir, "link")).to be_symlink(target: "#{long_dir}/#{unicode_file}")
    end
  end
end
