# frozen_string_literal: true

RSpec.describe MiniTarball::NullWriter do
  let(:io) { StringIO.new }

  describe ".write" do
    it "writes the specified number of null bytes" do
      described_class.write(io, 100)
      expect(io.string).to eq("\0" * 100)
    end

    it "does nothing for zero count" do
      described_class.write(io, 0)
      expect(io.string).to eq("")
    end

    it "does nothing for negative count" do
      described_class.write(io, -5)
      expect(io.string).to eq("")
    end

    it "writes in chunks for large sizes" do
      # Create a mock to verify chunked writing
      write_sizes = []
      mock_io =
        Object.new.tap do |obj|
          obj.define_singleton_method(:write) do |data|
            write_sizes << data.bytesize
            data.bytesize
          end
        end

      described_class.write(mock_io, 150_000)

      # Should be chunked (65536 + 65536 + 18928)
      expect(write_sizes).to eq([65_536, 65_536, 18_928])
    end

    it "handles exact chunk size" do
      described_class.write(io, 65_536)
      expect(io.string.bytesize).to eq(65_536)
      expect(io.string).to eq("\0" * 65_536)
    end
  end
end
