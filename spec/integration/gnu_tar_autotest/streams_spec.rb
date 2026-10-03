# frozen_string_literal: true

require_relative "spec_helper"

TarExtractor.extractors.each do |extractor|
  RSpec.describe "GNU tar Autotest streams (#{extractor.name})", :gnu_tar_autotest do
    include_context "with a GNU tar Autotest workspace"
    let(:tar_binary) { extractor.binary_path }

    describe "pipe.at", gnu_tar_source: "pipe.at" do
      it "extracts zero-filled and short members from stdin" do
        write_archive do |tar|
          tar.directory "dir"
          tar.file "dir/zeros", content: "\0" * 10_240
          tar.file "dir/short", content: "short content"
        end
        run_tar("-xf", "-", "-C", extract_dir, stdin_data: File.binread(archive_path))
        expect(extracted("dir/zeros")).to be_file(content: "\0" * 10_240)
        expect(extracted("dir/short")).to be_file(content: "short content")
      end

      it "accepts an archive written directly into a pipe" do
        content = (0..255).to_a.pack("C*") * 41
        Open3.popen3(
          { "TAR_OPTIONS" => nil },
          tar_binary,
          "-xf",
          "-",
          "-C",
          extract_dir,
        ) do |input, output, errors, process|
          MiniTarball::Writer.use(input) do |tar|
            tar.file("stream", size: content.bytesize) { |stream| stream.write(content) }
            tar.file "after", content: "after pipe"
          end
          expect(output.read).to eq("")
          diagnostics = errors.read
          expect(process.value.success?).to be(true), diagnostics
        end
        expect(File.binread(extracted("stream"))).to eq(content)
        expect(extracted("after")).to be_file(content: "after pipe")
      end
    end

    describe "shortrec.at", gnu_tar_source: "shortrec.at" do
      it "lists a compact archive from a file and stdin without record padding" do
        names = ("a".."r").map { |name| "dir/#{name}" }
        write_archive do |tar|
          tar.directory "dir"
          names.each { |name| tar.file name, content: "" }
        end
        expect(File.size(archive_path)).to eq((19 + 2) * 512)
        expected = ["dir/", *names].join("\n") + "\n"
        expect(run_tar("-tf", archive_path)).to eq(expected)
        expect(run_tar("-tf", "-", stdin_data: File.binread(archive_path))).to eq(expected)
        extract_archive
        names.each { |name| expect(extracted(name)).to be_file(content: "") }
      end
    end

    describe "compress.m4", gnu_tar_source: "compress.m4" do
      it "recognizes a gzip archive containing an empty file without a filename suffix" do
        Zlib::GzipWriter.open(archive_path) do |gzip|
          MiniTarball::Writer.use(gzip) { |tar| tar.file "empty", content: "" }
        end
        expect(run_tar("-tf", archive_path)).to eq("empty\n")
        extract_archive
        expect(extracted("empty")).to be_file(content: "")
      end
    end

    describe "comprec.at", gnu_tar_source: "comprec.at" do
      it "auto-detects gzip and restores streamed content and multiple entries" do
        content = (0..255).to_a.pack("C*") * 40
        Zlib::GzipWriter.open(archive_path) do |gzip|
          MiniTarball::Writer.use(gzip) do |tar|
            tar.directory "dir"
            tar.file("dir/data", size: content.bytesize) { |stream| stream.write(content) }
            tar.file("dir/after", size: 5) { |stream| stream.write("after") }
          end
        end
        extract_archive
        expect(extracted("dir")).to be_dir
        expect(File.binread(extracted("dir/data"))).to eq(content)
        expect(extracted("dir/after")).to be_file(content: "after")
      end
    end

    describe "truncate.at", gnu_tar_source: "truncate.at" do
      it "pads a short streamed member after raising and preserves the next member" do
        content = "x" * (195 * 1024)
        write_archive do |tar|
          expect {
            tar.file("short", size: 200 * 1024) { |stream| stream.write(content) }
          }.to raise_error(MiniTarball::IncompleteWriteError)
          tar.file "after", content: "after short write"
        end
        extract_archive
        expect(extracted("short")).to be_file(content: content + "\0" * (5 * 1024))
        expect(extracted("after")).to be_file(content: "after short write")
      end

      it "pads an explicitly permitted short write and preserves the next member" do
        write_archive do |tar|
          tar.file("short", size: 513, allow_short_writes: true) { |stream| stream.write("data") }
          tar.file "after", content: "after padding"
        end
        extract_archive
        expect(extracted("short")).to be_file(content: "data" + "\0" * 509)
        expect(extracted("after")).to be_file(content: "after padding")
      end
    end
  end
end
