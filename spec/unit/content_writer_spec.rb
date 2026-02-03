# frozen_string_literal: true

RSpec.describe MiniTarball::ContentWriter do
  let(:io) { StringIO.new.binmode }
  let(:header_writer) { MiniTarball::HeaderWriter.new(MiniTarball::WriteOnlyStream.new(io)) }
  let(:content_writer) { described_class.new(io, header_writer) }
  let(:attrs) { MiniTarball::EntryAttributes.with_file_defaults }

  describe "#write_capped" do
    it "pads remaining bytes with NULs" do
      content_writer.write_capped(io, size: 10) { |stream| stream.write("abc") }

      expect(io.string).to eq("abc" + ("\0" * 7))
    end
  end

  describe "#write_padding" do
    it "pads to the next 512-byte boundary" do
      io.write("x" * 600)

      content_writer.write_padding

      expect(io.string.bytesize).to eq(1024)
      expect(io.string).to have_null_padding(at: 600, bytes: 424)
    end
  end

  describe "#write_file" do
    it "writes header, content, and padding" do
      content_writer.write_file("test.txt", 3, attrs) { |stream| stream.write("abc") }

      expect(io.string.bytesize).to eq(1024)
      expect(io.string).to have_tar_header_field(:name, "test.txt")
      expect(io.string[512, 3]).to eq("abc")
      expect(io.string).to have_null_padding(at: 515, bytes: 509)
    end
  end
end
