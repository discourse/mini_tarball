# frozen_string_literal: true

require "tmpdir"
require "fileutils"

class ArchiveBuilder
  DEFAULT_MTIME = Time.utc(2024, 1, 1, 0, 0, 0)
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
      extract_dir = File.join(tmpdir, "extracted")
      FileUtils.mkdir_p(extract_dir)

      build_archive(archive_path)
      success = GnuTar.extract(archive_path, destination: extract_dir)

      yield extract_dir, success
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
      tar.add_directory(name: entry[:name], mode: entry[:mode], **default_metadata)
    when :file
      tar.add_file_from_stream(name: entry[:name], mode: entry[:mode], **default_metadata) do |io|
        io.write(entry[:content])
      end
    when :symlink
      tar.add_symlink(name: entry[:name], target: entry[:target], **default_metadata)
    when :hardlink
      tar.add_hardlink(name: entry[:name], target: entry[:target])
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
