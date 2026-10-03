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

    it "accepts a Shift_JIS name with a 0x5C byte inside a character" do
      # The second byte of "表" is 0x5C, the same byte as a backslash.
      expect { validate("表..".encode(Encoding::Shift_JIS)) }.not_to raise_error
    end

    context "with bytes that aren't valid in the encoding of the String" do
      it "accepts the path" do
        expect { validate("dir/f\xFF.txt") }.not_to raise_error
      end

      it "rejects absolute paths" do
        expect { validate("/\xFF") }.to raise_error(
          MiniTarball::UnsafeNameError,
          "Absolute paths are not allowed in #{label}: /\xFF",
        )
        expect { validate("C:\xFF") }.to raise_error(
          MiniTarball::UnsafeNameError,
          "Absolute paths are not allowed in #{label}: C:\xFF",
        )
        expect { validate("\\\\\xFF") }.to raise_error(
          MiniTarball::UnsafeNameError,
          "Absolute paths are not allowed in #{label}: \\\\\xFF",
        )
      end

      it "rejects path traversal" do
        expect { validate("../\xFF") }.to raise_error(
          MiniTarball::UnsafeNameError,
          "Path traversal is not allowed in #{label}: ../\xFF",
        )
        expect { validate("\xFF\\..\\x") }.to raise_error(
          MiniTarball::UnsafeNameError,
          "Path traversal is not allowed in #{label}: \xFF\\..\\x",
        )
      end

      it "rejects NUL bytes" do
        expect { validate("\xFF\0") }.to raise_error(
          MiniTarball::UnsafeNameError,
          "NUL bytes not allowed in #{label}",
        )
      end
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

  describe "error messages" do
    it "names the wrong type" do
      expect { described_class.validate_name!(:file) }.to raise_error(
        ArgumentError,
        "name must be a String, got Symbol",
      )
    end

    it "names the absolute path" do
      expect { described_class.validate_name!("/etc/passwd") }.to raise_error(
        MiniTarball::UnsafeNameError,
        "Absolute paths are not allowed in name: /etc/passwd",
      )
    end

    it "names the path with traversal" do
      expect { described_class.validate_target!("../x") }.to raise_error(
        MiniTarball::UnsafeNameError,
        "Path traversal is not allowed in target: ../x",
      )
    end
  end

  describe "with the writer" do
    let(:io) { StringIO.new.binmode }
    let(:name) { "f\xFF.txt" }

    it "writes a name with bytes that aren't valid in its encoding unchanged" do
      MiniTarball::Writer.use(io) { |writer| writer.file name, content: "x" }

      expect(io.string.byteslice(0, 100).delete("\0")).to eq(name.b)
    end

    it "writes a link target with bytes that aren't valid in its encoding unchanged" do
      MiniTarball::Writer.use(io) { |writer| writer.symlink "link", target: name }

      expect(io.string.byteslice(157, 100).delete("\0")).to eq(name.b)
    end

    it "writes a hard link target with bytes that aren't valid in its encoding unchanged" do
      MiniTarball::Writer.use(io) do |writer|
        writer.file name, content: "x"
        writer.hardlink "link", target: name
      end

      expect(io.string.byteslice(1024 + 157, 100).delete("\0")).to eq(name.b)
    end
  end

  it "accepts String subclasses" do
    expect { described_class.validate_name!(Class.new(String).new("file.txt")) }.not_to raise_error
  end
end
