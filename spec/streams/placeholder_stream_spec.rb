# frozen_string_literal: true

RSpec.describe MiniTarball::PlaceholderStream do
  let(:wrapped_io) { StringIO.new }
  let(:io) { MiniTarball::PlaceholderStream.new(wrapped_io, start_position: 10, file_size: 10) }

  it "allows writing at beginning of range" do
    wrapped_io.seek(10)
    io.write("foo")
    expect(wrapped_io.string).to eq("\0" * 10 + "foo" + "\0" * 7)
  end

  it "allows writing until the end of range" do
    wrapped_io.seek(17)
    io.write("foo")
    expect(wrapped_io.string).to eq("\0" * 17 + "foo")
  end

  it "allows writing within range" do
    wrapped_io.seek(15)
    io.write("foo")
    expect(wrapped_io.string).to eq("\0" * 15 + "foo" + "\0" * 2)
  end

  it "prevents writing when the content exceeds the range" do
    wrapped_io.seek(15)
    io.write("foo")
    expect { io.write("bar") }.to raise_error(MiniTarball::WriteOutOfRangeError)
    expect(wrapped_io.string).to eq("\0" * 15 + "foo" + "\0" * 2)
  end

  it "prevents writing outside of range" do
    expect { io.write("foo") }.to raise_error(MiniTarball::WriteOutOfRangeError)
    expect(wrapped_io.string).to be_empty

    wrapped_io.seek(20)
    expect { io.write("foo") }.to raise_error(MiniTarball::WriteOutOfRangeError)
    expect(wrapped_io.string).to be_empty
  end

  it "doesn't implement any methods except for `write`, `start_position` and `end_position`" do
    methods = io.public_methods - Object.public_methods
    expect(methods).to contain_exactly(:write, :start_position, :end_position)
  end
end
