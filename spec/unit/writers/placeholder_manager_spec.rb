# frozen_string_literal: true

require "forwardable"

RSpec.describe MiniTarball::PlaceholderManager do
  let(:io) { StringIO.new.binmode }
  let(:manager) { build_manager(io) }
  let(:no_source) { { from: nil, content: nil, block: nil } }

  def build_manager(io)
    header_writer = MiniTarball::HeaderWriter.new(MiniTarball::WriteOnlyStream.new(io))
    content_writer = MiniTarball::ContentWriter.new(io, header_writer)
    lookup = MiniTarball::UserGroupLookup::Cache.new
    entry_guard = ->(&block) { block.call }
    described_class.new(io:, header_writer:, content_writer:, lookup:, entry_guard:)
  end

  # Records every write, so tests can check which bytes a fill actually wrote.
  def track_writes(io)
    writes = []
    allow(io).to receive(:write).and_wrap_original do |original, data|
      writes << data.bytesize
      original.call(data)
    end
    writes
  end

  it "raises when filling a placeholder from another manager" do
    other_manager = build_manager(StringIO.new.binmode)
    placeholder = other_manager.reserve(name: "file.txt", size: 10)

    expect { manager.fill(placeholder, **no_source, content: "x") }.to raise_error(
      ArgumentError,
      "Placeholder does not belong to this writer",
    )
  end

  it "rejects content larger than the reservation before writing anything" do
    placeholder = manager.reserve(name: "file.txt", size: 10)
    before = io.string.dup

    expect {
      manager.fill(placeholder, **no_source, content: "x" * 11, mode: 0o600)
    }.to raise_error(MiniTarball::WriteOutOfRangeError, /11 bytes exceeds the reserved 10/)

    expect(io.string).to eq(before)
  end

  it "doesn't write NULs over the reservation again when filling it" do
    placeholder = manager.reserve(name: "file.txt", size: 100_000)
    writes = track_writes(io)

    manager.fill(placeholder, **no_source, content: "x")

    expect(writes.sum).to eq(512 + 1)
  end

  it "clears what an earlier failed fill wrote" do
    placeholder = manager.reserve(name: "file.txt", size: 100)

    expect {
      manager.fill(
        placeholder,
        **no_source,
        block:
          lambda do |stream|
            stream.write("y" * 50)
            raise "boom"
          end,
      )
    }.to raise_error("boom")
    manager.fill(placeholder, **no_source, content: "xx")

    expect(io.string[512, 100]).to eq("xx" + ("\0" * 98))
  end

  it "clears what an earlier failed fill wrote when the padding of the next fill failed" do
    placeholder = manager.reserve(name: "file.txt", size: 100)
    expect {
      manager.fill(
        placeholder,
        **no_source,
        block:
          lambda do |stream|
            stream.write("y" * 50)
            raise "boom"
          end,
      )
    }.to raise_error("boom")

    allow(io).to receive(:write).and_wrap_original do |original, data|
      raise IOError, "disk full" if data == "\0" * 49
      original.call(data)
    end
    expect { manager.fill(placeholder, **no_source, content: "x") }.to raise_error(
      IOError,
      "disk full",
    )
    allow(io).to receive(:write).and_call_original

    manager.fill(placeholder, **no_source, content: "z")

    expect(io.string[512, 100]).to eq("z" + ("\0" * 99))
  end

  it "fills a placeholder when the IO's write returns nil" do
    placeholder = manager.reserve(name: "file.txt", size: 10)
    allow(io).to receive(:write).and_wrap_original do |original, data|
      original.call(data)
      nil
    end

    manager.fill(placeholder, **no_source, content: "x")

    expect(io.string[512, 10]).to eq("x" + ("\0" * 9))
  end

  it "writes the reserved size into the header before the placeholder is filled" do
    manager.reserve(name: "file.txt", size: 10)

    expect(io.string).to have_tar_header_field(:size, 10)
  end

  it "writes only the header when an empty fill follows a fresh reservation" do
    placeholder = manager.reserve(name: "file.txt", size: 100)
    writes = track_writes(io)

    manager.fill(placeholder, **no_source, content: "")

    expect(writes.sum).to eq(512)
  end

  it "raises IOError when the IO was closed" do
    placeholder = manager.reserve(name: "file.txt", size: 10)
    io.close

    expect { manager.fill(placeholder, **no_source, content: "x") }.to raise_error(
      IOError,
      "Writer is closed",
    )
  end

  it "works with an IO that doesn't have closed?" do
    minimal_io =
      Class
        .new do
          extend Forwardable
          def_delegators :@io, :write, :pos, :seek, :string

          def initialize
            @io = StringIO.new.binmode
          end
        end
        .new
    manager = build_manager(minimal_io)
    placeholder = manager.reserve(name: "file.txt", size: 10)

    manager.fill(placeholder, **no_source, content: "x")

    expect(minimal_io.string[512]).to eq("x")
  end

  it "keeps the original error when writing the header fails" do
    placeholder = manager.reserve(name: "file.txt", size: 10)
    allow(io).to receive(:write).and_raise(IOError, "disk full")

    expect { manager.fill(placeholder, **no_source, content: "x") }.to raise_error(
      IOError,
      "disk full",
    )
  end
end
