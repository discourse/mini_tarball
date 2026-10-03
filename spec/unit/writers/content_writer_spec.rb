# frozen_string_literal: true

RSpec.describe MiniTarball::ContentWriter do
  let(:io) { StringIO.new.binmode }
  let(:header_writer) { MiniTarball::HeaderWriter.new(MiniTarball::WriteOnlyStream.new(io)) }
  let(:content_writer) { described_class.new(io, header_writer) }
  let(:attrs) { MiniTarball::EntryAttributes.with_file_defaults }

  describe "#write_capped" do
    it "pads remaining bytes with NULs" do
      content_writer.write_capped(size: 10) { |stream| stream.write("abc") }

      expect(io.string).to eq("abc" + ("\0" * 7))
    end

    it "writes at the current position of the writer's IO" do
      io.write("prefix")

      content_writer.write_capped(size: 4) { |stream| stream.write("ab") }

      expect(io.string).to eq("prefixab\0\0")
    end

    it "pads to the full size when the block raises" do
      expect {
        content_writer.write_capped(size: 10) do |stream|
          stream.write("abc")
          raise "boom"
        end
      }.to raise_error("boom")

      expect(io.string).to eq("abc" + ("\0" * 7))
    end
  end

  describe "#write_padding" do
    it "pads content of the given size to the next 512-byte boundary" do
      io.write("x" * 600)

      content_writer.write_padding(600)

      expect(io.string.bytesize).to eq(1024)
      expect(io.string).to have_null_padding(at: 600, bytes: 424)
    end

    it "writes nothing for content that ends on a block boundary" do
      content_writer.write_padding(1024)

      expect(io.string).to be_empty
    end
  end

  describe "#write_file" do
    it "writes header, content, and padding" do
      content_writer.write_file(name: "test.txt", size: 3, attrs:) { |stream| stream.write("abc") }

      expect(io.string.bytesize).to eq(1024)
      expect(io.string).to have_tar_header_field(:name, "test.txt")
      expect(io.string[512, 3]).to eq("abc")
      expect(io.string).to have_null_padding(at: 515, bytes: 509)
    end

    it "raises IncompleteWriteError when the block writes less than the declared size" do
      expect {
        content_writer.write_file(name: "test.txt", size: 10, attrs:) do |stream|
          stream.write("abc")
        end
      }.to raise_error(MiniTarball::IncompleteWriteError, /declared 10 bytes but only 3/)

      expect(io.string.bytesize).to eq(1024)
    end

    it "writes the entry when the IO's write returns nil" do
      allow(io).to receive(:write).and_wrap_original do |original, data|
        original.call(data)
        nil
      end

      content_writer.write_file(name: "test.txt", size: 3, attrs:) { |stream| stream.write("abc") }

      expect(io.string.bytesize).to eq(1024)
      expect(io.string[512, 3]).to eq("abc")
    end

    it "pads short writes when allow_short_writes is set" do
      content_writer.write_file(
        name: "test.txt",
        size: 10,
        attrs:,
        allow_short_writes: true,
      ) { |stream| stream.write("abc") }

      expect(io.string[512, 10]).to eq("abc" + ("\0" * 7))
    end
  end
end
