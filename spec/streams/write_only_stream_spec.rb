# frozen_string_literal: true

RSpec.describe MiniTarball::WriteOnlyStream do
  let(:wrapped_io) { StringIO.new }
  let(:io) { MiniTarball::WriteOnlyStream.new(wrapped_io) }

  it "allows writing" do
    io.write("Hello world!")
    expect(wrapped_io.string).to eq("Hello world!")
  end

  it "doesn't implement any methods except for 'write'" do
    methods = io.public_methods - Object.public_methods
    expect(methods).to contain_exactly(:write)
  end
end
