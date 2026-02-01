# frozen_string_literal: true

RSpec.describe MiniTarball::HeaderFields do
  describe "#to_binary" do
    it "returns a 512-byte binary string" do
      header = MiniTarball::Header.new(name: "test.txt", size: 0)
      fields = described_class.new(header)

      binary = fields.to_binary

      expect(binary.bytesize).to eq(512)
      expect(binary.encoding).to eq(Encoding::BINARY)
    end

    it "encodes the name field at the correct position" do
      header = MiniTarball::Header.new(name: "myfile.txt", size: 0)
      fields = described_class.new(header)

      binary = fields.to_binary

      # Name field is at offset 0, length 100
      expect(binary[0, 10]).to eq("myfile.txt")
    end

    it "encodes numeric fields in octal" do
      attrs =
        MiniTarball::EntryAttributes.new(
          mode: 0644,
          uid: nil,
          gid: nil,
          uname: nil,
          gname: nil,
          mtime: nil,
        )
      header = MiniTarball::Header.new(name: "test.txt", size: 1234, attrs:)
      fields = described_class.new(header)

      binary = fields.to_binary

      # Mode field is at offset 100, length 8
      expect(binary[100, 7]).to eq("0000644")
      # Size field is at offset 124, length 12
      expect(binary[124, 11]).to eq("00000002322") # 1234 in octal
    end

    it "computes and includes the checksum" do
      header = MiniTarball::Header.new(name: "test.txt", size: 0)
      fields = described_class.new(header)

      binary = fields.to_binary

      # Checksum field is at offset 148, length 8
      checksum_field = binary[148, 8]
      expect(checksum_field).to match(/\A\d{6}\0 \z/)
    end

    it "pads the output to exactly 512 bytes" do
      header = MiniTarball::Header.new(name: "x", size: 0)
      fields = described_class.new(header)

      binary = fields.to_binary

      expect(binary.bytesize).to eq(512)
      # Trailing bytes should be NUL
      expect(binary[-10, 10]).to eq("\0" * 10)
    end

    it "handles all tar header field types" do
      attrs =
        MiniTarball::EntryAttributes.new(
          mode: 0755,
          uid: 1000,
          gid: 1000,
          uname: "user",
          gname: "group",
          mtime: Time.utc(2020, 1, 1),
        )
      header =
        MiniTarball::Header.new(
          name: "file.txt",
          size: 100,
          typeflag: MiniTarball::Header::TYPE_REGULAR,
          linkname: "",
          attrs:,
        )
      fields = described_class.new(header)

      binary = fields.to_binary

      expect(binary.bytesize).to eq(512)
      expect(binary[0, 8]).to eq("file.txt")
      expect(binary[100, 7]).to eq("0000755")
      expect(binary[265, 4]).to eq("user")
      expect(binary[297, 5]).to eq("group")
    end
  end
end
