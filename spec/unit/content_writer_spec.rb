# frozen_string_literal: true

RSpec.describe MiniTarball::ContentWriter do
  let(:io) { StringIO.new.binmode }
  let(:header_writer) { MiniTarball::HeaderWriter.new(MiniTarball::WriteOnlyStream.new(io)) }
  let(:attrs) { MiniTarball::EntryAttributes.with_file_defaults }

  describe "#write_capped" do
    it "pads remaining bytes with NULs" do
      described_class
        .new(io, header_writer)
        .write_capped(io, size: 10) { |stream| stream.write("abc") }

      expect(io.string).to eq("abc" + ("\0" * 7))
    end
  end

  describe "#write_padding" do
    it "pads to the next 512-byte boundary" do
      io.write("x" * 600)

      described_class.new(io, header_writer).write_padding

      expect(io.string.bytesize).to eq(1024)
      expect(io.string[600, 424]).to eq("\0" * 424)
    end
  end

  describe "#write_file" do
    it "writes header, content, and padding" do
      described_class
        .new(io, header_writer)
        .write_file("test.txt", 3, attrs) { |stream| stream.write("abc") }

      expect(io.string.bytesize).to eq(1024)
      expect(io.string[512, 3]).to eq("abc")
    end
  end
end
