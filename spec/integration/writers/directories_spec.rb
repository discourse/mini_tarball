# frozen_string_literal: true

require_relative "../../integration_helper"

RSpec.describe "Directories" do
  it "extracts an empty directory" do
    build_archive { directory "empty" }.with_extraction do |dir|
      expect(File.join(dir, "empty")).to be_dir
    end
  end

  it "extracts nested directories" do
    build_archive do
      directory "a"
      directory "a/b"
      directory "a/b/c"
    end.with_extraction { |dir| expect(File.join(dir, "a/b/c")).to be_dir }
  end

  it "preserves directory permissions" do
    build_archive { directory "restricted", mode: 0o700 }.with_extraction do |dir|
      expect(File.join(dir, "restricted")).to have_mode(0o700)
    end
  end
end
