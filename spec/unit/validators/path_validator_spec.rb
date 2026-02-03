# frozen_string_literal: true

RSpec.describe MiniTarball::PathValidator do
  shared_examples "path validation" do |method, label|
    define_method(:validate) { |path| described_class.public_send(method, path) }

    it "accepts simple filenames" do
      expect { validate("file.txt") }.not_to raise_error
    end

    it "accepts relative paths" do
      expect { validate("foo/bar/file.txt") }.not_to raise_error
    end

    it "rejects nil" do
      expect { validate(nil) }.to raise_error(
        MiniTarball::UnsafeNameError,
        "Empty #{label} not allowed",
      )
    end

    it "rejects empty string" do
      expect { validate("") }.to raise_error(
        MiniTarball::UnsafeNameError,
        "Empty #{label} not allowed",
      )
    end

    it "rejects absolute Unix paths" do
      expect { validate("/etc/passwd") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Absolute paths are not allowed in #{label}/,
      )
    end

    it "rejects absolute Windows paths with drive letter" do
      expect { validate("C:\\Windows\\System32") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Absolute paths are not allowed in #{label}/,
      )
    end

    it "rejects Windows drive-relative paths" do
      expect { validate("C:foo") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Absolute paths are not allowed in #{label}/,
      )
    end

    it "rejects Windows UNC paths" do
      expect { validate("\\\\server\\share") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Absolute paths are not allowed in #{label}/,
      )
    end

    it "rejects path traversal at start" do
      expect { validate("../etc/passwd") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Path traversal is not allowed in #{label}/,
      )
    end

    it "rejects path traversal in middle" do
      expect { validate("foo/../../../etc/passwd") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Path traversal is not allowed in #{label}/,
      )
    end

    it "rejects bare .." do
      expect { validate("..") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Path traversal is not allowed in #{label}/,
      )
    end

    it "rejects path ending with /.." do
      expect { validate("foo/bar/..") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Path traversal is not allowed in #{label}/,
      )
    end

    it "rejects path traversal with backslashes" do
      expect { validate("foo\\..\\..\\etc") }.to raise_error(
        MiniTarball::UnsafeNameError,
        /Path traversal is not allowed in #{label}/,
      )
    end

    it "rejects NUL bytes" do
      expect { validate("file\0.txt") }.to raise_error(
        MiniTarball::UnsafeNameError,
        "NUL bytes not allowed in #{label}",
      )
    end

    it "rejects embedded NUL bytes" do
      expect { validate("foo/bar\0/baz.txt") }.to raise_error(
        MiniTarball::UnsafeNameError,
        "NUL bytes not allowed in #{label}",
      )
    end
  end

  describe ".validate_name!" do
    include_examples "path validation", :validate_name!, "name"
  end

  describe ".validate_target!" do
    include_examples "path validation", :validate_target!, "target"

    it "allows path traversal when explicitly permitted" do
      expect {
        described_class.validate_target!("../other/file.txt", allow_parent_references: true)
      }.not_to raise_error
    end
  end
end
