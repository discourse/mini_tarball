# frozen_string_literal: true

require "tempfile"
require "time"

RSpec.describe MiniTarball::Placeholder do
  let(:io) { StringIO.new.binmode }

  let(:default_options) do
    {
      mode: 0644,
      mtime: Time.parse("2021-02-15T20:11:34Z"),
      uname: "discourse",
      gname: "www-data",
      uid: 1001,
      gid: 33,
    }
  end

  describe "#fill" do
    it "fills placeholder with string content" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 100
        placeholder.fill content: "hello world", **default_options
      end

      expect(io.string).to have_tar_header_field(:name, "test.txt")
      expect(io.string[512, 11]).to eq("hello world")
    end

    it "fills placeholder from file" do
      Tempfile.create do |tempfile|
        tempfile.binmode
        tempfile.write("file content")
        tempfile.flush

        MiniTarball::Writer.use(io) do |writer|
          placeholder = writer.placeholder "test.txt", size: 100
          placeholder.fill from: tempfile.path
        end

        expect(io.string[512, 12]).to eq("file content")
      end
    end

    it "fills placeholder via streaming" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 100
        placeholder.fill(**default_options) do |stream|
          stream.write("streamed ")
          stream.write("content")
        end
      end

      expect(io.string[512, 16]).to eq("streamed content")
    end

    it "raises when already filled" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 100

        placeholder.fill content: "first", **default_options

        expect { placeholder.fill content: "second" }.to raise_error(
          ArgumentError,
          /already filled/,
        )
      end
    end

    it "raises when content exceeds reserved size" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 5

        expect { placeholder.fill content: "too long content", **default_options }.to raise_error(
          MiniTarball::WriteOutOfRangeError,
        )

        # Fill with valid content so close doesn't raise
        placeholder.fill content: "ok", **default_options
      end
    end

    it "raises when file content exceeds reserved size" do
      Tempfile.create do |tempfile|
        tempfile.binmode
        tempfile.write("too long content")
        tempfile.flush

        MiniTarball::Writer.use(io) do |writer|
          placeholder = writer.placeholder "test.txt", size: 5

          expect { placeholder.fill from: tempfile.path }.to raise_error(
            MiniTarball::WriteOutOfRangeError,
          )

          # Fill with valid content so close doesn't raise
          placeholder.fill content: "ok", **default_options
        end
      end
    end

    it "raises when streaming content exceeds reserved size" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 5

        expect {
          placeholder.fill(**default_options) { |stream| stream.write("too long") }
        }.to raise_error(MiniTarball::WriteOutOfRangeError)

        # Fill with valid content so close doesn't raise
        placeholder.fill content: "ok", **default_options
      end
    end

    it "raises with helpful message when no source provided" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 100

        expect { placeholder.fill(**default_options) }.to raise_error(
          ArgumentError,
          /Provide exactly one of/,
        )

        # Still need to fill it for clean close
        placeholder.fill content: "x"
      end
    end

    it "raises with helpful message when multiple sources provided" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 100

        expect {
          placeholder.fill(content: "x", **default_options) { |s| s.write("y") }
        }.to raise_error(ArgumentError, /Provide exactly one of/)

        placeholder.fill content: "x"
      end
    end

    it "pads with NUL when content is smaller than reserved size" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 20
        placeholder.fill content: "short", **default_options
      end

      content = io.string[512, 20]
      expect(content[0, 5]).to eq("short")
      expect(content[5, 15]).to eq("\0" * 15)
    end

    it "raises Errno::ENOENT when source file does not exist" do
      writer = MiniTarball::Writer.new(io)
      placeholder = writer.placeholder "test.txt", size: 100

      expect { placeholder.fill from: "/nonexistent/path/file.txt" }.to raise_error(Errno::ENOENT)

      # Fill with valid content so close doesn't raise
      placeholder.fill content: "x"
      writer.close
    end

    it "uses file stat attributes when filling from file without overrides" do
      Tempfile.create do |tempfile|
        tempfile.binmode
        tempfile.write("hello")
        tempfile.flush

        stat =
          instance_double(
            File::Stat,
            mode: 0o100640,
            uid: 123,
            gid: 456,
            mtime: Time.parse("2020-01-02T03:04:05Z"),
          )

        # Mock File.open to return a file that yields our mock stat
        original_open = File.method(:open)
        allow(File).to receive(:open).with(tempfile.path, "rb") do |&block|
          original_open.call(tempfile.path, "rb") do |f|
            allow(f).to receive(:stat).and_return(stat)
            block.call(f)
          end
        end

        allow(MiniTarball::UserGroupLookup).to receive(:username).with(123).and_return("alice")
        allow(MiniTarball::UserGroupLookup).to receive(:groupname).with(456).and_return("staff")

        MiniTarball::Writer.use(io) do |writer|
          placeholder = writer.placeholder "file.txt", size: 5
          placeholder.fill from: tempfile.path
        end

        expect(io.string).to have_tar_header_field(:mode, format("%07o", stat.mode & 0o7777))
        expect(io.string).to have_tar_header_field(:uid, format("%07o", stat.uid))
        expect(io.string).to have_tar_header_field(:gid, format("%07o", stat.gid))
        expect(io.string).to have_tar_header_field(:uname, "alice")
        expect(io.string).to have_tar_header_field(:gname, "staff")
      end
    end

    it "uses default file attributes when filling with content" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 100
        placeholder.fill content: "test"
      end

      expect(io.string).to have_tar_header_field(:mode, "0000644")
      expect(io.string).to have_tar_header_field(:uname, "nobody")
      expect(io.string).to have_tar_header_field(:gname, "nogroup")
    end

    it "allows setting attributes at fill time" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 100
        placeholder.fill content: "test", mode: 0755
      end

      expect(io.string).to have_tar_header_field(:mode, "0000755")
    end

    it "returns self for chaining" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 100
        result = placeholder.fill(content: "test", **default_options)
        expect(result).to eq(placeholder)
      end
    end
  end

  describe "#filled?" do
    it "returns false before filling" do
      writer = MiniTarball::Writer.new(io)
      placeholder = writer.placeholder "test.txt", size: 100

      expect(placeholder.filled?).to be false

      placeholder.fill content: "x"
      writer.close
    end

    it "returns true after filling" do
      MiniTarball::Writer.use(io) do |writer|
        placeholder = writer.placeholder "test.txt", size: 100
        placeholder.fill content: "x", **default_options

        expect(placeholder.filled?).to be true
      end
    end
  end

  describe "#name" do
    it "returns the reserved name" do
      writer = MiniTarball::Writer.new(io)
      placeholder = writer.placeholder "my_file.txt", size: 100

      expect(placeholder.name).to eq("my_file.txt")

      placeholder.fill content: "x"
      writer.close
    end
  end
end
