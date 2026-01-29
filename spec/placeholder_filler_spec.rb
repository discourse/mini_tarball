# frozen_string_literal: true

RSpec.describe MiniTarball::PlaceholderFiller do
  let(:io) { StringIO.new }
  let(:writer) { MiniTarball::Writer.new(io) }
  let(:filler) { described_class.new(writer) }

  describe "allowed methods" do
    it "responds to add_file" do
      expect(filler).to respond_to(:add_file)
    end

    it "responds to add_file_from_stream" do
      expect(filler).to respond_to(:add_file_from_stream)
    end
  end

  describe "prevented methods" do
    it "does not respond to reserve" do
      expect(filler).not_to respond_to(:reserve)
    end

    it "does not respond to fill" do
      expect(filler).not_to respond_to(:fill)
    end

    it "does not respond to close" do
      expect(filler).not_to respond_to(:close)
    end

    it "does not respond to add_directory" do
      expect(filler).not_to respond_to(:add_directory)
    end

    it "does not respond to add_symlink" do
      expect(filler).not_to respond_to(:add_symlink)
    end

    it "does not respond to add_hardlink" do
      expect(filler).not_to respond_to(:add_hardlink)
    end
  end

  describe "chaining" do
    it "returns self from add_file_from_stream" do
      result = filler.add_file_from_stream(name: "test.txt") { |s| s.write("hello") }
      expect(result).to be(filler)
    end
  end

  describe "integration with Writer#fill" do
    it "yields a PlaceholderFiller, not the Writer" do
      placeholder = writer.reserve(name: "test.txt", size: 100)

      yielded_object = nil
      writer.fill(placeholder) { |f| yielded_object = f }

      expect(yielded_object).to be_a(described_class)
      expect(yielded_object).not_to be(writer)
    end
  end
end
