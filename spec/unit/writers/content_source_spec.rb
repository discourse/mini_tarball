# frozen_string_literal: true

require "pathname"
require "tempfile"
require "timeout"
require "tmpdir"

RSpec.describe MiniTarball::ContentSource do
  let(:lookup) { MiniTarball::UserGroupLookup::Cache.new }
  let(:source_file) do
    Tempfile.create.tap do |file|
      file.binmode
      file.write("hello")
      file.flush
    end
  end

  after { File.unlink(source_file.path) if File.exist?(source_file.path) }

  def open_source(from: nil, content: nil, block: nil, **attrs)
    described_class.open(from:, content:, block:, lookup:, **attrs) { |source| yield source }
  end

  def written(source)
    StringIO.new.binmode.tap { |io| source.write_to(io) }.string
  end

  describe "with content:" do
    it "knows the size and writes the string" do
      open_source(content: "hello") do |source|
        expect(source.size).to eq(5)
        expect(written(source)).to eq("hello")
      end
    end

    it "uses file defaults for attributes" do
      open_source(content: "x") do |source|
        expect(source.attrs.mode).to eq(0o644)
        expect(source.attrs.uname).to eq("nobody")
      end
    end
  end

  describe "with a block" do
    it "has no size and calls the block" do
      open_source(block: ->(stream) { stream.write("streamed") }) do |source|
        expect(source.size).to be_nil
        expect(written(source)).to eq("streamed")
      end
    end
  end

  describe "with from:" do
    it "takes size and attributes from the open file" do
      open_source(from: source_file.path) do |source|
        expect(source.size).to eq(5)
        expect(source.attrs.mode).to eq(File.stat(source_file.path).mode)
        expect(written(source)).to eq("hello")
      end
    end

    it "applies attribute overrides" do
      open_source(from: source_file.path, mode: 0o600, uname: "alice") do |source|
        expect(source.attrs.mode).to eq(0o600)
        expect(source.attrs.uname).to eq("alice")
      end
    end

    it "leaves the names empty for owner IDs that are too large for the system lookup" do
      open_source(from: source_file.path, uid: 5_000_000_000, gid: 5_000_000_000) do |source|
        expect(source.attrs).to have_attributes(
          uid: 5_000_000_000,
          gid: 5_000_000_000,
          uname: "",
          gname: "",
        )
      end
    end

    it "rejects directories before yielding" do
      Dir.mktmpdir do |dir|
        expect { open_source(from: dir) { raise "must not yield" } }.to raise_error(
          ArgumentError,
          /from: must be a regular file/,
        )
      end
    end

    it "rejects a FIFO without opening it" do
      Dir.mktmpdir do |dir|
        fifo = File.join(dir, "fifo")
        File.mkfifo(fifo)

        Timeout.timeout(5) do
          expect { open_source(from: fifo) { raise "must not yield" } }.to raise_error(
            ArgumentError,
            "from: must be a regular file: #{fifo}",
          )
        end
      end
    end

    it "checks the opened file again in case the path changed after the check" do
      Dir.mktmpdir do |dir|
        file_stat = File.stat(source_file.path)
        allow(File).to receive(:stat).and_call_original
        allow(File).to receive(:stat).with(dir).and_return(file_stat)

        expect { open_source(from: dir) { raise "must not yield" } }.to raise_error(
          ArgumentError,
          "from: must be a regular file: #{dir}",
        )
      end
    end

    it "accepts a Pathname" do
      open_source(from: Pathname.new(source_file.path)) do |source|
        expect(source.size).to eq(5)
        expect(written(source)).to eq("hello")
      end
    end

    it "names the path of an object with to_path in errors" do
      Dir.mktmpdir do |dir|
        path = Object.new
        path.define_singleton_method(:to_path) { dir }

        expect { open_source(from: path) { nil } }.to raise_error(
          ArgumentError,
          "from: must be a regular file: #{dir}",
        )
      end
    end

    it "names the path of an object with to_path when the file changed" do
      source_path = source_file.path
      path = Object.new
      path.define_singleton_method(:to_path) { source_path }

      open_source(from: path) do |source|
        File.write(source_file.path, " world", mode: "ab")

        expect { written(source) }.to raise_error(
          MiniTarball::FileChangedError,
          "#{source_file.path} changed while it was being archived (expected 5 bytes)",
        )
      end
    end

    it "raises when the file grows after its size was read" do
      open_source(from: source_file.path) do |source|
        File.write(source_file.path, " world", mode: "ab")

        expect { written(source) }.to raise_error(
          MiniTarball::FileChangedError,
          "#{source_file.path} changed while it was being archived (expected 5 bytes)",
        )
      end
    end

    it "raises when the file shrinks after its size was read" do
      open_source(from: source_file.path) do |source|
        File.truncate(source_file.path, 3)

        expect { written(source) }.to raise_error(
          MiniTarball::FileChangedError,
          "#{source_file.path} changed while it was being archived (expected 5 bytes)",
        )
      end
    end

    it "copies only the size from the stat when the file grows" do
      stream = StringIO.new.binmode

      open_source(from: source_file.path) do |source|
        File.write(source_file.path, " world", mode: "ab")
        expect { source.write_to(stream) }.to raise_error(MiniTarball::FileChangedError)
      end

      expect(stream.string).to eq("hello")
    end

    it "copies an empty file" do
      File.truncate(source_file.path, 0)

      open_source(from: source_file.path) do |source|
        expect(source.size).to eq(0)
        expect(written(source)).to eq("")
      end
    end

    it "looks up each owner only once per lookup cache" do
      allow(MiniTarball::UserGroupLookup).to receive_messages(username: "alice", groupname: "staff")

      3.times { open_source(from: source_file.path) { nil } }

      expect(MiniTarball::UserGroupLookup).to have_received(:username).once
      expect(MiniTarball::UserGroupLookup).to have_received(:groupname).once
    end
  end

  it "rejects more than one source" do
    expect { open_source(from: source_file.path, content: "x") { nil } }.to raise_error(
      ArgumentError,
      /exactly one/,
    )
  end

  it "names the path that isn't a regular file" do
    Dir.mktmpdir do |dir|
      expect { open_source(from: dir) { nil } }.to raise_error(
        ArgumentError,
        "from: must be a regular file: #{dir}",
      )
    end
  end
end
