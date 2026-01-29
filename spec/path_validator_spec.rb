# frozen_string_literal: true

RSpec.describe MiniTarball::PathValidator do
  describe ".validate_name!" do
    it "accepts simple filenames" do
      expect { described_class.validate_name!("file.txt") }.not_to raise_error
    end

    it "accepts relative paths" do
      expect { described_class.validate_name!("foo/bar/file.txt") }.not_to raise_error
    end

    it "rejects nil" do
      expect { described_class.validate_name!(nil) }.to raise_error(
        MiniTarball::UnsafeNameError,
        "Empty name not allowed",
      )
    end

    it "rejects empty string" do
      expect { described_class.validate_name!("") }.to raise_error(
        MiniTarball::UnsafeNameError,
        "Empty name not allowed",
      )
    end

    it "rejects absolute Unix paths" do
      expect { described_class.validate_name!("/etc/passwd") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Absolute paths are not allowed/,
      )
    end

    it "rejects absolute Windows paths with drive letter" do
      expect { described_class.validate_name!("C:\\Windows\\System32") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Absolute paths are not allowed/,
      )
    end

    it "rejects Windows UNC paths" do
      expect { described_class.validate_name!("\\\\server\\share") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Absolute paths are not allowed/,
      )
    end

    it "rejects path traversal with .." do
      expect { described_class.validate_name!("../etc/passwd") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Path traversal is not allowed/,
      )
    end

    it "rejects path traversal in middle of path" do
      expect { described_class.validate_name!("foo/../../../etc/passwd") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Path traversal is not allowed/,
      )
    end

    it "rejects bare .." do
      expect { described_class.validate_name!("..") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Path traversal is not allowed/,
      )
    end

    it "rejects path traversal with backslashes" do
      expect { described_class.validate_name!("foo\\..\\..\\etc") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Path traversal is not allowed/,
      )
    end
  end

  describe ".validate_target!" do
    it "accepts simple targets" do
      expect { described_class.validate_target!("file.txt") }.not_to raise_error
    end

    it "accepts relative targets with .." do
      expect { described_class.validate_target!("../other/file.txt") }.not_to raise_error
    end

    it "rejects nil" do
      expect { described_class.validate_target!(nil) }.to raise_error(
        MiniTarball::UnsafeNameError,
        "Empty target not allowed",
      )
    end

    it "rejects empty string" do
      expect { described_class.validate_target!("") }.to raise_error(
        MiniTarball::UnsafeNameError,
        "Empty target not allowed",
      )
    end

    it "rejects absolute Unix paths" do
      expect { described_class.validate_target!("/etc/passwd") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Absolute target paths are not allowed/,
      )
    end

    it "rejects absolute Windows paths" do
      expect { described_class.validate_target!("C:\\Windows") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Absolute target paths are not allowed/,
      )
    end
  end

  describe ".absolute_path?" do
    it "returns true for Unix absolute paths" do
      expect(described_class.absolute_path?("/etc/passwd")).to be true
    end

    it "returns true for Windows drive paths" do
      expect(described_class.absolute_path?("C:\\Windows")).to be true
      expect(described_class.absolute_path?("D:/Documents")).to be true
    end

    it "returns true for Windows UNC paths" do
      expect(described_class.absolute_path?("\\\\server\\share")).to be true
    end

    it "returns false for relative paths" do
      expect(described_class.absolute_path?("foo/bar")).to be false
      expect(described_class.absolute_path?("file.txt")).to be false
    end
  end

  describe ".path_traversal?" do
    it "returns true for bare .." do
      expect(described_class.path_traversal?("..")).to be true
    end

    it "returns true for ../ prefix" do
      expect(described_class.path_traversal?("../foo")).to be true
    end

    it "returns true for /.. suffix" do
      expect(described_class.path_traversal?("foo/..")).to be true
    end

    it "returns true for /../ in middle" do
      expect(described_class.path_traversal?("foo/../bar")).to be true
    end

    it "returns true for backslash traversal" do
      expect(described_class.path_traversal?("foo\\..\\bar")).to be true
    end

    it "returns false for safe paths" do
      expect(described_class.path_traversal?("foo/bar")).to be false
      expect(described_class.path_traversal?("..foo")).to be false
      expect(described_class.path_traversal?("foo..")).to be false
    end
  end
end
