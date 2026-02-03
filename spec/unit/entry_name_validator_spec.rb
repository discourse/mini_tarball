# frozen_string_literal: true

RSpec.describe MiniTarball do
  describe ".validate_name!" do
    it "accepts normal filenames" do
      expect { described_class.validate_name!("file.txt") }.not_to raise_error
    end

    it "rejects absolute paths" do
      expect { described_class.validate_name!("/etc/passwd") }.to raise_error(
        MiniTarball::PathTraversalError,
      )
    end

    it "rejects path traversal" do
      expect { described_class.validate_name!("../escape.txt") }.to raise_error(
        MiniTarball::PathTraversalError,
      )
    end
  end

end
