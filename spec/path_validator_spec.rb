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
end
