# frozen_string_literal: true

require_relative "../integration_helper"

RSpec.describe "Writer error recovery" do
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

  def extract_with_all(archive_path)
    Dir.mktmpdir do |tmpdir|
      TarExtractor.each_extractor(tmpdir:) do |ctx|
        raise "#{ctx.name} failed to extract #{archive_path}" unless ctx.extract(archive_path)
        yield ctx.extract_dir
      end
    end
  end

  it "keeps archive aligned when a sized streaming block raises" do
    Dir.mktmpdir do |tmpdir|
      archive_path = File.join(tmpdir, "test.tar")

      File.open(archive_path, "wb") do |file|
        writer = MiniTarball::Writer.new(file)

        expect {
          writer.file("bad.txt", size: 10, **default_options) { |_s| raise "boom" }
        }.to raise_error(RuntimeError, "boom")

        writer.file("good.txt", content: "ok", **default_options)
        writer.close
      end

      extract_with_all(archive_path) do |dir|
        expect(File.read(File.join(dir, "good.txt"))).to eq("ok")
        expect(File.binread(File.join(dir, "bad.txt"))).to eq("\0" * 10)
      end
    end
  end

  it "keeps archive aligned when a seekable streaming block raises without size" do
    Dir.mktmpdir do |tmpdir|
      archive_path = File.join(tmpdir, "test.tar")

      File.open(archive_path, "wb") do |file|
        writer = MiniTarball::Writer.new(file)

        expect {
          writer.file("bad.txt", **default_options) do |stream|
            stream.write("partial")
            raise "boom"
          end
        }.to raise_error(RuntimeError, "boom")

        writer.file("good.txt", content: "ok", **default_options)
        writer.close
      end

      extract_with_all(archive_path) do |dir|
        expect(File.read(File.join(dir, "good.txt"))).to eq("ok")
        expect(File.read(File.join(dir, "bad.txt"))).to eq("partial")
      end
    end
  end

  it "recovers after exceptions in placeholder fill blocks" do
    Dir.mktmpdir do |tmpdir|
      archive_path = File.join(tmpdir, "test.tar")

      MiniTarball::Writer.create(archive_path) do |writer|
        placeholder = writer.placeholder "placeholder.txt", size: 100
        writer.file "file2.txt",
                    content: File.binread(fixture_path("files/file2.txt")),
                    **default_options

        expect { placeholder.fill { |_s| raise "simulated error" } }.to raise_error(
          RuntimeError,
          "simulated error",
        )

        placeholder.fill content: "ok", **default_options

        writer.file "file3.txt",
                    content: File.binread(fixture_path("files/file3.txt")),
                    **default_options
      end

      extract_with_all(archive_path) do |dir|
        expect(File.join(dir, "file2.txt")).to be_file
        expect(File.join(dir, "file3.txt")).to be_file

        placeholder_content = File.binread(File.join(dir, "placeholder.txt"))
        expect(placeholder_content.bytesize).to eq(100)
        expect(placeholder_content[0, 2]).to eq("ok")
      end
    end
  end
end
