# frozen_string_literal: true

require_relative "../integration/support/gnu_tar"

RSpec.describe GnuTar do
  describe ".available?" do
    before do
      described_class.instance_variable_set(:@binary_path, nil)
      described_class.instance_variable_set(:@version, nil)
    end

    it "returns false when version is below minimum" do
      allow(described_class).to receive(:binary_path).and_return("/usr/bin/tar")
      allow(described_class).to receive(:version).and_return("1.25")

      expect(described_class.available?).to be false
    end

    it "returns false when version is nil" do
      allow(described_class).to receive(:binary_path).and_return("/usr/bin/tar")
      allow(described_class).to receive(:version).and_return(nil)

      expect(described_class.available?).to be false
    end

    it "returns true when version meets minimum" do
      allow(described_class).to receive(:binary_path).and_return("/usr/bin/tar")
      allow(described_class).to receive(:version).and_return("1.26")

      expect(described_class.available?).to be true
    end
  end
end
