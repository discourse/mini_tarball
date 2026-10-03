# frozen_string_literal: true

require "pathname"

RSpec.describe MiniTarball::SourceValidator do
  describe ".validate!" do
    it "accepts exactly one source" do
      expect {
        described_class.validate!(from: "path", content: nil, block: nil)
      }.not_to raise_error
      expect {
        described_class.validate!(from: nil, content: "content", block: nil)
      }.not_to raise_error
      expect {
        described_class.validate!(from: nil, content: nil, block: ->(_s) {})
      }.not_to raise_error
    end

    it "raises when no sources are provided" do
      expect { described_class.validate!(from: nil, content: nil, block: nil) }.to raise_error(
        ArgumentError,
        /Provide exactly one of/,
      )
    end

    it "raises when multiple sources are provided" do
      expect {
        described_class.validate!(from: "path", content: "content", block: nil)
      }.to raise_error(ArgumentError, /Provide exactly one of/)
    end

    it "raises when from is not a path" do
      expect { described_class.validate!(from: 123, content: nil, block: nil) }.to raise_error(
        ArgumentError,
        "from: must be a String or respond to to_path",
      )
    end

    it "accepts a Pathname for from" do
      expect {
        described_class.validate!(from: Pathname.new("path"), content: nil, block: nil)
      }.not_to raise_error
    end

    it "accepts an object with to_path for from" do
      path = Object.new
      path.define_singleton_method(:to_path) { "path" }

      expect { described_class.validate!(from: path, content: nil, block: nil) }.not_to raise_error
    end

    it "rejects a Pathname for content" do
      expect {
        described_class.validate!(from: nil, content: Pathname.new("path"), block: nil)
      }.to raise_error(ArgumentError, "content: must be a String")
    end

    it "raises when content is not a String" do
      expect { described_class.validate!(from: nil, content: :content, block: nil) }.to raise_error(
        ArgumentError,
        "content: must be a String",
      )
    end
  end

  it "accepts String subclasses" do
    subclass = Class.new(String)

    expect {
      described_class.validate!(from: nil, content: subclass.new("x"), block: nil)
    }.not_to raise_error
  end
end
