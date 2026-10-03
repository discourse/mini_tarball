# frozen_string_literal: true

RSpec.describe MiniTarball::HeaderFormatter do
  describe ".format_number" do
    def format(value, length)
      described_class.format_number(value, length)
    end

    it "returns nil if the value is nil" do
      expect(format(nil, 10)).to eq(nil)
    end

    context "with octal" do
      it "returns an octal number as long as it fits the length" do
        expect(format(0, 8)).to eq("0000000")
        expect(format(1, 8)).to eq("0000001")
        expect(format(0o7777777, 8)).to eq("7777777")
        expect(format(0o10_000_000, 8)).to_not eq("10000000")
      end
    end

    context "with base-256" do
      let(:max_octal_8) { (8**7) - 1 }

      it "encodes the value big-endian after a leading 0x80 byte" do
        expect(format(max_octal_8 + 1, 8)).to eq("\x80\x00\x00\x00\x00\x20\x00\x00".b)
        expect(format((2**40) + 5, 12)).to eq("\x80\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x05".b)
      end

      it "raises an exception if the value is too large to encode into the given length" do
        too_large = 1 << 56
        expect { format(too_large, 8) }.to raise_error(MiniTarball::ValueTooLargeError)
      end

      it "reports the original value and field length in the error" do
        expect { format(2**100, 12) }.to raise_error(
          MiniTarball::ValueTooLargeError,
          "Value is too large for a 12-byte header field: #{2**100}",
        )
      end

      it "accepts the largest value that fits into the given length" do
        expect(format((256**7) - 1, 8)).to eq("\x80#{"\xFF" * 7}".b)
        expect { format(256**7, 8) }.to raise_error(MiniTarball::ValueTooLargeError)
      end
    end

    context "with negative numbers" do
      it "encodes them as two's complement with a leading 0xFF byte" do
        expect(format(-1, 12)).to eq(("\xFF" * 12).b)
        expect(format(-1, 8)).to eq(("\xFF" * 8).b)
        expect(format(-0x01_02_03_04_05, 12)).to eq("#{"\xFF" * 7}\xFE\xFD\xFC\xFB\xFB".b)
      end

      it "returns a binary String" do
        expect(format(-1, 12).encoding).to eq(Encoding::BINARY)
      end

      it "accepts the smallest value that fits into the given length" do
        expect(format(-(256**11), 12)).to eq("\xFF#{"\0" * 11}".b)
        expect(format(-(256**7), 8)).to eq("\xFF#{"\0" * 7}".b)
      end

      it "raises an exception if the value doesn't fit into the given length" do
        expect { format(-(256**11) - 1, 12) }.to raise_error(
          MiniTarball::ValueTooLargeError,
          "Value is too large for a 12-byte header field: #{-(256**11) - 1}",
        )
        expect { format(-(256**7) - 1, 8) }.to raise_error(MiniTarball::ValueTooLargeError)
      end

      it "raises an exception for unsupported field lengths" do
        expect { format(-1, 5) }.to raise_error(ArgumentError, "Unsupported octal field length: 5")
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

  describe "error messages" do
    it "names an unsupported field length" do
      expect { described_class.format_number(1, 5) }.to raise_error(
        ArgumentError,
        "Unsupported octal field length: 5",
      )
    end
  end

  describe ".format_checksum" do
    it "returns spaces for the whole field when there is no checksum yet" do
      expect(described_class.format_checksum(nil)).to eq(" " * 8)
    end

    it "returns the same frozen string for every header without a checksum" do
      empty = described_class.format_checksum(nil)

      expect(empty).to be_frozen
      expect(described_class.format_checksum(nil)).to equal(empty)
    end

    it "returns six octal digits followed by a NUL and a space" do
      expect(described_class.format_checksum(0o1234)).to eq("001234\0 ")
    end
  end

  describe ".zero_pad" do
    it "pads to the next block boundary" do
      expect(described_class.zero_pad("a")).to eq("a" + ("\0" * 511))
    end

    it "pads data longer than one block to the next boundary" do
      expect(described_class.zero_pad("a" * 513).bytesize).to eq(1024)
    end

    it "doesn't pad data that already ends on a block boundary" do
      expect(described_class.zero_pad("a" * 512)).to eq("a" * 512)
    end
  end
end
