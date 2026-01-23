# frozen_string_literal: true

RSpec.describe MiniTarball::HeaderParser do
  def create_tar_with_file(content)
    io = StringIO.new.binmode
    MiniTarball::Writer.use(io) do |writer|
      writer.add_file_from_stream(
        name: "test.txt",
        mode: 0644,
        uname: "user",
        gname: "group",
      ) { |s| s.write(content) }
    end
    io.string
  end

  describe ".parse" do
    it "parses a valid header" do
      tar_data = create_tar_with_file("hello")
      header_data = tar_data[0, 512]

      values = described_class.parse(header_data)

      expect(values[:name]).to eq("test.txt")
      expect(values[:size]).to eq(5)
      expect(values[:mode]).to eq(0644)
      expect(values[:uname]).to eq("user")
      expect(values[:gname]).to eq("group")
      expect(values[:typeflag]).to eq("0")
    end

    it "returns nil for nil input" do
      expect(described_class.parse(nil)).to be_nil
    end

    it "returns nil for data shorter than block size" do
      expect(described_class.parse("short")).to be_nil
    end

    it "returns nil for end-of-archive marker" do
      expect(described_class.parse("\0" * 512)).to be_nil
    end

    it "raises ChecksumMismatchError for corrupted header" do
      tar_data = create_tar_with_file("hello")
      header_data = tar_data[0, 512]
      # Corrupt the header
      corrupted = header_data.dup
      corrupted[0] = "X"

      expect { described_class.parse(corrupted) }.to raise_error(MiniTarball::ChecksumMismatchError)
    end
  end

  describe ".end_of_archive?" do
    it "returns true for null block" do
      expect(described_class.end_of_archive?("\0" * 512)).to be true
    end

    it "returns false for non-null data" do
      expect(described_class.end_of_archive?("a" * 512)).to be false
    end
  end

  context "with base-256 encoded size" do
    it "parses large file sizes correctly" do
      # Create a header with base-256 encoded size
      # This is tested indirectly through the Writer which uses base-256 for large files
      io = StringIO.new.binmode
      MiniTarball::Writer.use(io) do |writer|
        # Use add_file_from_stream with a large declared size
        writer.add_file_from_stream(name: "big.txt", size: 8_589_934_592) do |s|
          # Don't actually write 8GB, just test the header
        end
      end

      header_data = io.string[0, 512]
      values = described_class.parse(header_data)

      expect(values[:size]).to eq(8_589_934_592)
    end
  end
end
