# frozen_string_literal: true

RSpec.describe MiniTarball::HeaderFormatter do
  def format(value, length)
    described_class.format_number(value, length)
  end

  describe ".format_number" do
    it "returns nil if the value is nil" do
      expect(format(nil, 10)).to eq(nil)
    end

    it "raises an exception if the value is negative" do
      expect { format(-1, 10) }.to raise_error(NotImplementedError)
    end

    context "octal" do
      it "returns a string with length - 1" do
        expect(format(10, 5).length).to eq(4)
      end

      it "returns an octal number as long as it fits the length" do
        expect(format(0, 5)).to eq("0000")
        expect(format(1, 5)).to eq("0001")
        expect(format(4095, 5)).to eq("7777")
        expect(format(4096, 5)).to_not eq("10000")
      end
    end

    context "base-256" do
      it "returns a string with the correct length" do
        expect(format(4096, 5).length).to eq(5)
      end

      it "returns a string where the leading byte is 0x80" do
        expect(format(4096, 5)).to start_with(0x80.chr)
      end

      it "returns an encoded number" do
        expect(format(4096, 5)).to eq([0x80, 0x00, 0x00, 0x10, 0x00].pack("C*"))
        expect(format(269_488_144, 5)).to eq([0x80, 0x10, 0x10, 0x10, 0x10].pack("C*"))
        expect(format(42_949_67_295, 5)).to eq([0x80, 0xFF, 0xFF, 0xFF, 0xFF].pack("C*"))
        expect(format(42_949_67_296, 6)).to eq([0x80, 0x01, 0x00, 0x00, 0x00, 0x00].pack("C*"))
      end

      it "raises an exception if the value is too large to encode into the given length" do
        expect { format(65_536, 3) }.to raise_error(MiniTarball::ValueTooLargeError)
        expect { format(42_949_67_296, 5) }.to raise_error(MiniTarball::ValueTooLargeError)
      end
    end
  end
end
