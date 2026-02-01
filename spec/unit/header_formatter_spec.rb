# frozen_string_literal: true

RSpec.describe MiniTarball::HeaderFormatter do
  describe ".format_number" do
    def format(value, length)
      described_class.format_number(value, length)
    end

    it "returns nil if the value is nil" do
      expect(format(nil, 10)).to eq(nil)
    end

    it "raises an exception if the value is negative" do
      expect { format(-1, 10) }.to raise_error(ArgumentError, /Negative numbers are not supported/)
    end

    context "with octal" do
      it "returns a string with length - 1" do
        expect(format(10, 8).length).to eq(7)
      end

      it "returns an octal number as long as it fits the length" do
        expect(format(0, 8)).to eq("0000000")
        expect(format(1, 8)).to eq("0000001")
        expect(format(0o7777777, 8)).to eq("7777777")
        expect(format(0o10_000_000, 8)).to_not eq("10000000")
      end
    end

    context "with base-256" do
      it "returns a string with the correct length" do
        expect(format(4096, 8).length).to eq(8)
      end

      it "returns a string where the leading byte is 0x80" do
        expect(format(4096, 8)).to start_with(0x80.chr)
      end

      it "returns an encoded number" do
        expect(format(4096, 8)).to eq([0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00].pack("C*"))
        expect(format(269_488_144, 8)).to eq(
          [0x80, 0x00, 0x00, 0x00, 0x10, 0x10, 0x10, 0x10].pack("C*"),
        )
        expect(format(0x7F_FF_FF_FF_FF_FF, 8)).to eq(
          [0x80, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF].pack("C*"),
        )
        expect(format(0x80_00_00_00_00_00, 12)).to eq(
          [0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00].pack("C*"),
        )
      end

      it "raises an exception if the value is too large to encode into the given length" do
        expect { format(0x1_00_00_00_00_00_00, 8) }.to raise_error(MiniTarball::ValueTooLargeError)
      end
    end

    it "raises an exception for unsupported field lengths" do
      expect { format(10, 5) }.to raise_error(ArgumentError, /Unsupported octal field length/)
    end
  end

  describe ".format_permissions" do
    def format_permissions(value)
      described_class.format_permissions(value, 7)
    end

    it "removes file type bitfields" do
      expect(format_permissions(0140777)).to eq("000777") # socket
      expect(format_permissions(0120777)).to eq("000777") # symbolic link
      expect(format_permissions(0100777)).to eq("000777") # regular file
      expect(format_permissions(0060777)).to eq("000777") # block device
      expect(format_permissions(0040777)).to eq("000777") # directory
      expect(format_permissions(0020777)).to eq("000777") # character device
      expect(format_permissions(0010777)).to eq("000777") # fifo
    end

    it "keeps permission bitfields" do
      expect(format_permissions(04000)).to eq("004000") # set UID bit
      expect(format_permissions(02000)).to eq("002000") # set GID bit
      expect(format_permissions(01000)).to eq("001000") # sticky bit

      expect(format_permissions(0400)).to eq("000400") # owner has read permission
      expect(format_permissions(0200)).to eq("000200") # owner has write permission
      expect(format_permissions(0100)).to eq("000100") # owner has execute permission
      expect(format_permissions(0040)).to eq("000040") # group has read permission
      expect(format_permissions(0020)).to eq("000020") # group has write permission
      expect(format_permissions(0010)).to eq("000010") # group has execute permission
      expect(format_permissions(0004)).to eq("000004") # others have read permission
      expect(format_permissions(0002)).to eq("000002") # others have write permisson
      expect(format_permissions(0001)).to eq("000001") # others have execute permission
    end
  end
end
