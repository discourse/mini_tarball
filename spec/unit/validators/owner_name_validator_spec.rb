# frozen_string_literal: true

RSpec.describe MiniTarball::OwnerNameValidator do
  it "has the same field size for uname and gname" do
    fields = MiniTarball::Header::FIELDS

    expect(fields.fetch(:gname).fetch(:length)).to eq(fields.fetch(:uname).fetch(:length))
  end

  describe "with a different field size in the header" do
    before do
      fields = MiniTarball::Header::FIELDS.merge(uname: { length: 4, type: :chars })
      stub_const("MiniTarball::Header::FIELDS", fields)
    end

    it "uses the size of the uname header field" do
      expect(described_class.valid?("abcd")).to be(true)
      expect(described_class.valid?("abcde")).to be(false)
    end

    it "names the size in the error message" do
      expect { described_class.validate!("abcde", label: "uname") }.to raise_error(
        ArgumentError,
        'uname must be a String of at most 4 bytes without control characters: "abcde"',
      )
    end
  end

  describe ".valid?" do
    it "accepts names up to the field size" do
      expect(described_class.valid?("")).to be(true)
      expect(described_class.valid?("a" * 32)).to be(true)
    end

    it "counts bytes, not characters" do
      expect(described_class.valid?("ä" * 16)).to be(true)
      expect(described_class.valid?("ä" * 17)).to be(false)
    end

    it "rejects longer names, control characters and non-Strings" do
      expect(described_class.valid?("a" * 33)).to be(false)
      expect(described_class.valid?("a\nb")).to be(false)
      expect(described_class.valid?("a\0b")).to be(false)
      expect(described_class.valid?(:alice)).to be(false)
    end

    it "rejects Unicode control characters in valid UTF-8" do
      expect(described_class.valid?("alice\u0085")).to be(false)
    end

    context "with bytes that aren't valid in the encoding of the String" do
      it "accepts the name as bytes" do
        expect(described_class.valid?("alice\xFF")).to be(true)
        expect(described_class.valid?("\xFF" * 32)).to be(true)
      end

      it "rejects longer names and control characters" do
        expect(described_class.valid?("\xFF" * 33)).to be(false)
        expect(described_class.valid?("alice\xFF\n")).to be(false)
      end
    end
  end

  describe ".validate!" do
    it "allows nil, which means the name isn't set" do
      expect { described_class.validate!(nil, label: "uname") }.not_to raise_error
    end

    it "raises with the label for invalid names" do
      expect { described_class.validate!("a\tb", label: "gname") }.to raise_error(
        ArgumentError,
        /gname must be a String of at most 32 bytes/,
      )
    end
  end

  it "writes a name with bytes that aren't valid in its encoding unchanged" do
    io = StringIO.new.binmode
    MiniTarball::Writer.use(io) do |writer|
      writer.file "file.txt", content: "x", uname: "alice\xFF", gname: "staff\xFF"
    end

    expect(io.string.byteslice(265, 32).delete("\0")).to eq("alice\xFF".b)
    expect(io.string.byteslice(297, 32).delete("\0")).to eq("staff\xFF".b)
  end

  it "accepts String subclasses" do
    expect(described_class.valid?(Class.new(String).new("alice"))).to be(true)
  end
end
