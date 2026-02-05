# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe MiniTarball::ExtractionValidator do
  let(:tmpdir) { Dir.mktmpdir("extraction_validator_test") }

  after { FileUtils.rm_rf(tmpdir) }

  describe ".validate_extraction_path!" do
    it "accepts paths within destination" do
      result = described_class.validate_extraction_path!("file.txt", tmpdir)
      expect(result).to eq(File.join(tmpdir, "file.txt"))
    end

    it "accepts nested paths within destination" do
      result = described_class.validate_extraction_path!("dir/subdir/file.txt", tmpdir)
      expect(result).to eq(File.join(tmpdir, "dir/subdir/file.txt"))
    end

    it "rejects paths that traverse above destination" do
      expect { described_class.validate_extraction_path!("../escape.txt", tmpdir) }.to raise_error(
        MiniTarball::PathTraversalError,
        /escapes destination/,
      )
    end

    it "rejects paths with embedded traversal" do
      expect {
        described_class.validate_extraction_path!("dir/../../../escape.txt", tmpdir)
      }.to raise_error(MiniTarball::PathTraversalError, /escapes destination/)
    end

    it "rejects absolute paths" do
      expect { described_class.validate_extraction_path!("/etc/passwd", tmpdir) }.to raise_error(
        MiniTarball::PathTraversalError,
        /escapes destination/,
      )
    end

    it "handles paths that normalize to destination" do
      result = described_class.validate_extraction_path!("dir/../file.txt", tmpdir)
      expect(result).to eq(File.join(tmpdir, "file.txt"))
    end

    it "rejects paths that traverse symlink components" do
      File.symlink("/", File.join(tmpdir, "escape"))

      expect {
        described_class.validate_extraction_path!("escape/etc/passwd", tmpdir)
      }.to raise_error(MiniTarball::PathTraversalError, /Symlink component/)
    end

    it "rejects existing symlink at final path by default" do
      File.symlink("target.txt", File.join(tmpdir, "link.txt"))

      expect {
        described_class.validate_extraction_path!("link.txt", tmpdir)
      }.to raise_error(MiniTarball::PathTraversalError, /Symlink component/)
    end

    it "allows existing symlink at final path when configured" do
      File.symlink("target.txt", File.join(tmpdir, "link.txt"))

      result =
        described_class.validate_extraction_path!(
          "link.txt",
          tmpdir,
          allow_final_symlink: true,
        )

      expect(result).to eq(File.join(tmpdir, "link.txt"))
    end
  end

  describe ".validate_symlink_target!" do
    let(:link_path) { File.join(tmpdir, "subdir/link.txt") }

    before { FileUtils.mkdir_p(File.join(tmpdir, "subdir")) }

    it "accepts relative targets within destination" do
      result =
        described_class.validate_symlink_target!(
          link_path: link_path,
          target: "../file.txt",
          destination: tmpdir,
        )
      expect(result).to eq("../file.txt")
    end

    it "accepts targets in same directory" do
      result =
        described_class.validate_symlink_target!(
          link_path: link_path,
          target: "target.txt",
          destination: tmpdir,
        )
      expect(result).to eq("target.txt")
    end

    it "rejects absolute symlink targets" do
      expect {
        described_class.validate_symlink_target!(
          link_path: link_path,
          target: "/etc/passwd",
          destination: tmpdir,
        )
      }.to raise_error(MiniTarball::PathTraversalError, /Absolute symlink/)
    end

    it "rejects Windows absolute symlink targets" do
      expect {
        described_class.validate_symlink_target!(
          link_path: link_path,
          target: "C:\\Windows\\System32",
          destination: tmpdir,
        )
      }.to raise_error(MiniTarball::PathTraversalError, /Absolute symlink/)
    end

    it "rejects symlinks that escape destination" do
      expect {
        described_class.validate_symlink_target!(
          link_path: link_path,
          target: "../../escape.txt",
          destination: tmpdir,
        )
      }.to raise_error(MiniTarball::PathTraversalError, /escapes destination/)
    end
  end

  describe ".validate_name_components!" do
    it "accepts normal filenames" do
      expect { described_class.validate_name_components!("file.txt") }.not_to raise_error
    end

    it "accepts paths with directories" do
      expect { described_class.validate_name_components!("dir/file.txt") }.not_to raise_error
    end

    it "rejects absolute Unix paths" do
      expect { described_class.validate_name_components!("/etc/passwd") }.to raise_error(
        MiniTarball::PathTraversalError,
        /Absolute path/,
      )
    end

    it "rejects absolute Windows paths" do
      expect { described_class.validate_name_components!("C:\\Windows\\System32") }.to raise_error(
        MiniTarball::PathTraversalError,
        /Absolute path/,
      )
    end

    it "rejects paths with null bytes" do
      expect { described_class.validate_name_components!("file\0.txt") }.to raise_error(
        MiniTarball::PathTraversalError,
        /NUL bytes/,
      )
    end

    it "rejects Windows-style traversal" do
      expect {
        described_class.validate_name_components!("dir\\..\\..\\escape.txt")
      }.to raise_error(MiniTarball::PathTraversalError, /traversal/)
    end
  end
end
