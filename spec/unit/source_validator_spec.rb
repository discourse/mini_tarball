# frozen_string_literal: true

RSpec.describe MiniTarball::SourceValidator do
  describe ".validate!" do
    it "accepts exactly one source" do
      expect { described_class.validate!("path", nil, nil) }.not_to raise_error
      expect { described_class.validate!(nil, "content", nil) }.not_to raise_error
      expect { described_class.validate!(nil, nil, ->(_s) {}) }.not_to raise_error
    end

    it "raises when no sources are provided" do
      expect { described_class.validate!(nil, nil, nil) }.to raise_error(
        ArgumentError,
        /Provide exactly one of/,
      )
    end

    it "raises when multiple sources are provided" do
      expect { described_class.validate!("path", "content", nil) }.to raise_error(
        ArgumentError,
        /Provide exactly one of/,
      )
    end
  end
end
