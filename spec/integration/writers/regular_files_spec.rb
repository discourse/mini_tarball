# frozen_string_literal: true

require_relative "../../integration_helper"

RSpec.describe "Regular files" do
  it "extracts a simple text file" do
    build_archive { file "hello.txt", content: "Hello, World!" }.with_extraction do |dir|
      expect(File.join(dir, "hello.txt")).to be_file(content: "Hello, World!")
    end
  end

  it "extracts binary content" do
    binary = (0..255).to_a.pack("C*")
    build_archive { file "binary.bin", content: binary }.with_extraction do |dir|
      expect(File.read(File.join(dir, "binary.bin"), mode: "rb")).to eq(binary)
    end
  end

  it "extracts files in subdirectories" do
    build_archive { file "subdir/nested.txt", content: "nested content" }.with_extraction do |dir|
      expect(File.join(dir, "subdir/nested.txt")).to be_file(content: "nested content")
    end
  end

  it "preserves file permissions" do
    build_archive do
      file "executable.sh", content: "#!/bin/sh", mode: 0o755
    end.with_extraction { |dir| expect(File.join(dir, "executable.sh")).to have_mode(0o755) }
  end
end
