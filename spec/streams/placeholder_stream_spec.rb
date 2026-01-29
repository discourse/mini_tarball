# frozen_string_literal: true

RSpec.describe MiniTarball::PlaceholderStream do
  class RecordingIO
    attr_reader :writes

    def initialize
      @writes = []
      @pos = 0
    end

    def pos
      @pos
    end

    def seek(offset)
      @pos = offset
    end

    def write(data)
      @writes << data
      @pos += data.bytesize
      data.bytesize
    end
  end

  let(:wrapped_io) { StringIO.new }
  let(:io) { MiniTarball::PlaceholderStream.new(wrapped_io, start_position: 10, size: 10) }

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

  it "only exposes write, <<, start_position and end_position methods" do
    methods = io.public_methods - Object.public_methods
    expect(methods).to contain_exactly(:write, :<<, :start_position, :end_position)
  end

  it "does not write padding when already at end" do
    recording_io = RecordingIO.new
    stream = MiniTarball::PlaceholderStream.new(recording_io, start_position: 10, size: 3)
    recording_io.seek(10)

    stream.write("abc")

    expect(recording_io.writes).to eq(["abc"])
  end

  it "returns the total bytes written without padding" do
    recording_io = RecordingIO.new
    stream = MiniTarball::PlaceholderStream.new(recording_io, start_position: 10, size: 5)
    recording_io.seek(10)

    bytes_written = stream.write("ab")

    expect(bytes_written).to eq(2)
  end
end
