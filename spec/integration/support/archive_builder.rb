# frozen_string_literal: true

require "tmpdir"
require "fileutils"

class ArchiveBuilder
  DEFAULT_MTIME = Time.utc(2024, 1, 1, 0, 0, 0).freeze
  DEFAULT_UID = 1000
  DEFAULT_GID = 1000
  DEFAULT_UNAME = "user"
  DEFAULT_GNAME = "group"

  def initialize
    @entries = []
  end

  def directory(name, mode: 0o755)
    @entries << { type: :directory, name:, mode: }
    self
  end

  def file(name, content: "", mode: 0o644)
    @entries << { type: :file, name:, content:, mode: }
    self
  end

  def symlink(name, target:)
    @entries << { type: :symlink, name:, target: }
    self
  end

  def hardlink(name, target:)
    @entries << { type: :hardlink, name:, target: }
    self
  end

  def with_extraction
    Dir.mktmpdir do |tmpdir|
      archive_path = File.join(tmpdir, "test.tar")
      build_archive(archive_path)

      TarExtractor.each_extractor(tmpdir:) do |ctx|
        success = ctx.extract(archive_path)
        yield ctx.extract_dir, success, ctx.name
      end
    end
  end

  private

  def build_archive(archive_path)
    MiniTarball::Writer.create(archive_path) do |tar|
      @entries.each { |entry| add_entry(tar, entry) }
    end
  end

  def add_entry(tar, entry)
    case entry[:type]
    when :directory
      tar.directory entry[:name], mode: entry[:mode], **default_metadata
    when :file
      tar.file entry[:name], content: entry[:content], mode: entry[:mode], **default_metadata
    when :symlink
      tar.symlink entry[:name], target: entry[:target], **default_metadata
    when :hardlink
      tar.hardlink entry[:name], target: entry[:target], **default_metadata
    end
  end

  def default_metadata
    {
      mtime: DEFAULT_MTIME,
      uid: DEFAULT_UID,
      gid: DEFAULT_GID,
      uname: DEFAULT_UNAME,
      gname: DEFAULT_GNAME,
    }
  end
end

def build_archive(&)
  builder = ArchiveBuilder.new
  builder.instance_eval(&)
  builder
end
