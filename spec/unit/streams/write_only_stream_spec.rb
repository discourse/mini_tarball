# frozen_string_literal: true

RSpec.describe MiniTarball::WriteOnlyStream do
  subject(:stream) { described_class.new(wrapped_io) }

  let(:wrapped_io) { StringIO.new }

  it "allows writing" do
    stream.write("Hello world!")
    expect(wrapped_io.string).to eq("Hello world!")
  end

  it "supports << operator for chaining" do
    stream << "Hello" << " " << "world!"
    expect(wrapped_io.string).to eq("Hello world!")
  end

  it "only exposes write and << methods" do
    methods = stream.public_methods - Object.public_methods
    expect(methods).to contain_exactly(:write, :<<)
  end
end
