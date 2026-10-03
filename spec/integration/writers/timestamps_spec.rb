# frozen_string_literal: true

require "open3"
require_relative "../../integration_helper"

RSpec.describe "Timestamps" do
  let(:before_1970) { Time.utc(1969, 12, 31, 23, 59, 59) }

  def build_archive_at(dir, &)
    archive_path = File.join(dir, "test.tar")
    MiniTarball::Writer.create(archive_path, &)
    archive_path
  end

  def gnu_tar_listing(archive_path)
    output, status =
      Open3.capture2({ "TZ" => "UTC" }, GnuTar.binary_path, "--full-time", "-tvf", archive_path)
    raise "GNU tar failed to list #{archive_path}" unless status.success?
    output
  end

  def extracted_mtimes(archive_path, name)
    mtimes = {}
    Dir.mktmpdir do |tmpdir|
      TarExtractor.each_extractor(tmpdir:) do |ctx|
        raise "#{ctx.name} failed to extract #{archive_path}" unless ctx.extract(archive_path)
        mtimes[ctx.name] = file_mtime(File.join(ctx.extract_dir, name))
      end
    end
    mtimes
  end

  # TruffleRuby can't read file times before 1970
  def file_mtime(path)
    File.mtime(path).to_i
  rescue RangeError
    skip "This Ruby can't read file times before 1970"
  end

  def for_all_extractors(mtime)
    TarExtractor.extractors.to_h { |extractor| [extractor.name, mtime.to_i] }
  end

  it "lists an mtime before 1970 with GNU tar" do
    Dir.mktmpdir do |dir|
      archive_path =
        build_archive_at(dir) { |writer| writer.file "old.txt", content: "x", mtime: before_1970 }

      expect(gnu_tar_listing(archive_path)).to include("1969-12-31 23:59:59 old.txt")
    end
  end

  it "extracts an mtime before 1970" do
    Dir.mktmpdir do |dir|
      archive_path =
        build_archive_at(dir) do |writer|
          writer.file "one.txt", content: "x", mtime: Time.at(-1).utc
          writer.file "old.txt", content: "x", mtime: Time.utc(1901, 1, 1)
        end

      expect(extracted_mtimes(archive_path, "one.txt")).to eq(for_all_extractors(-1))
      expect(extracted_mtimes(archive_path, "old.txt")).to eq(
        for_all_extractors(Time.utc(1901, 1, 1)),
      )
    end
  end

  it "writes the same mtime field as GNU tar" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "old.txt")
      File.write(source, "x")
      gnu_archive = File.join(dir, "gnu.tar")
      GnuTar.create(gnu_archive, files: ["old.txt"], chdir: dir, mtime: "@-1")
      archive_path =
        build_archive_at(dir) { |writer| writer.file "old.txt", from: source, mtime: -1 }

      expect(File.binread(archive_path, 12, 136)).to eq(File.binread(gnu_archive, 12, 136))
    end
  end

  it "reads an mtime before 1970 from a file" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "old.txt")
      File.write(source, "x")
      File.utime(before_1970, before_1970, source)
      if file_mtime(source) != before_1970.to_i
        skip "The file system doesn't store times before 1970"
      end

      archive_path = build_archive_at(dir) { |writer| writer.file "old.txt", from: source }

      expect(gnu_tar_listing(archive_path)).to include("1969-12-31 23:59:59 old.txt")
      expect(extracted_mtimes(archive_path, "old.txt")).to eq(for_all_extractors(before_1970))
    end
  end
end
