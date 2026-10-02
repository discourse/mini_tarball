# frozen_string_literal: true

require "tempfile"
require "tmpdir"

def build_custom_archive(
  name: "file.txt",
  typeflag: MiniTarball::Header::TYPE[:regular],
  content: "content",
  pad: true,
  end_blocks: true
)
  io = StringIO.new(String.new, "w+b")
  attrs = MiniTarball::EntryAttributes.with_file_defaults
  header = MiniTarball::Header.new(name:, size: content.bytesize, typeflag:, attrs:)

  MiniTarball::HeaderWriter.new(io).write(header)
  io.write(content)

  if pad
    padding =
      (MiniTarball::Header::BLOCK_SIZE - (content.bytesize % MiniTarball::Header::BLOCK_SIZE)) %
        MiniTarball::Header::BLOCK_SIZE
    io.write("\0" * padding)
  end

  io.write("\0" * (MiniTarball::Header::BLOCK_SIZE * 2)) if end_blocks
  io.rewind
  io
end

def build_pax_record(key, value)
  data = "#{key}=#{value}\n"
  length = data.bytesize + 2

  loop do
    record = "#{length} #{data}"
    return record if record.bytesize == length
    length = record.bytesize
  end
end

def write_entry(io, header, content)
  MiniTarball::HeaderWriter.new(io).write(header)
  io.write(content)
  io.write("\0" * MiniTarball::Header.padding_for(content.bytesize))
end

def build_pax_size_override_archive
  io = StringIO.new(String.new, "w+b")
  attrs = MiniTarball::EntryAttributes.with_file_defaults

  pax_record = build_pax_record("size", "4")
  pax_header =
    MiniTarball::Header.new(
      name: "pax",
      size: pax_record.bytesize,
      typeflag: MiniTarball::Header::TYPE[:pax_extended],
      attrs:,
    )
  write_entry(io, pax_header, pax_record)

  file_header =
    MiniTarball::Header.new(
      name: "file.txt",
      size: 1,
      typeflag: MiniTarball::Header::TYPE[:regular],
      attrs:,
    )
  write_entry(io, file_header, "DATA")

  io.write("\0" * MiniTarball::Header::END_OF_ARCHIVE_SIZE)
  io.rewind
  io
end

def build_gnu_and_pax_archive
  io = StringIO.new(String.new, "w+b")
  attrs = MiniTarball::EntryAttributes.with_file_defaults

  long_name = ("a" * 120) + ".txt"
  write_entry(io, MiniTarball::Header.long_link_header(long_name), "#{long_name}\0")

  pax_record = build_pax_record("path", "pax_name.txt")
  pax_header =
    MiniTarball::Header.new(
      name: "pax",
      size: pax_record.bytesize,
      typeflag: MiniTarball::Header::TYPE[:pax_extended],
      attrs:,
    )
  write_entry(io, pax_header, pax_record)

  file_header =
    MiniTarball::Header.new(
      name: "short.txt",
      size: 3,
      typeflag: MiniTarball::Header::TYPE[:regular],
      attrs:,
    )
  write_entry(io, file_header, "abc")

  io.write("\0" * MiniTarball::Header::END_OF_ARCHIVE_SIZE)
  io.rewind
  io
end

RSpec.describe MiniTarball::Reader do
  let(:archive_data) { fixture("archives/multiple_files.tar") }
  let(:io) { StringIO.new(archive_data) }

  describe ".open" do
    it "opens a file and yields a reader" do
      Tempfile.create("reader_test") do |tempfile|
        tempfile.write(archive_data)
        tempfile.close

        entries = []
        described_class.open(tempfile.path) do |reader|
          reader.each_entry { |entry, _| entries << entry.name }
        end

        expect(entries).to eq(%w[file1.txt file2.txt file3.txt])
      end
    end

    it "closes the file when done" do
      Tempfile.create("reader_test") do |tempfile|
        tempfile.write(archive_data)
        tempfile.close

        reader_instance = nil
        described_class.open(tempfile.path) { |r| reader_instance = r }

        expect(reader_instance.closed?).to be true
      end
    end
  end

  describe ".use" do
    it "yields a reader and closes it when done" do
      reader_instance = nil
      described_class.use(io) { |r| reader_instance = r }

      expect(reader_instance.closed?).to be true
    end

    it "closes the reader even if an error is raised" do
      reader_instance = nil

      expect {
        described_class.use(io) do |r|
          reader_instance = r
          raise "boom"
        end
      }.to raise_error("boom")

      expect(reader_instance.closed?).to be true
    end
  end

  describe "#each_entry" do
    it "yields each entry with a stream" do
      entries = []
      contents = []

      described_class.use(io) do |reader|
        reader.each_entry do |entry, stream|
          entries << entry.name
          contents << stream.read
        end
      end

      expect(entries).to eq(%w[file1.txt file2.txt file3.txt])
      expect(contents[0]).to start_with("aaaaaaaaaaaaaaaa")
    end

    it "provides entry metadata" do
      described_class.use(io) do |reader|
        reader.each_entry do |entry, _|
          expect(entry.mode).to eq(0644)
          expect(entry.uid).to eq(1001)
          expect(entry.gid).to eq(33)
          expect(entry.uname).to eq("discourse")
          expect(entry.gname).to eq("www-data")
          break
        end
      end
    end

    it "returns an Enumerator when no block given" do
      described_class.use(io) do |reader|
        enum = reader.each_entry
        expect(enum).to be_an(Enumerator)

        names = enum.map { |entry, _| entry.name }
        expect(names).to eq(%w[file1.txt file2.txt file3.txt])
      end
    end

    it "handles archives with no entries" do
      empty_archive = "\0" * 1024
      io = StringIO.new(empty_archive)

      entries = []
      described_class.use(io) { |reader| reader.each_entry { |entry, _| entries << entry } }

      expect(entries).to be_empty
    end
  end

  describe "GNU long name support" do
    it "handles filenames longer than 100 bytes" do
      long_name_archive = fixture("headers/exactly_101_byte_name_header")
      # This fixture is 3 blocks: LongLink header + name data + actual file header
      # We need to add content and end-of-archive to make it a valid archive
      archive = long_name_archive + "foo" + "\0" * (512 - 3) + "\0" * 1024
      io = StringIO.new(archive)

      entry_name = nil
      described_class.use(io) { |reader| reader.each_entry { |entry, _| entry_name = entry.name } }

      expect(entry_name).to eq("a" * 97 + ".txt")
    end
  end

  describe "pax headers" do
    it "uses pax size overrides for content length" do
      io = build_pax_size_override_archive
      data = nil

      described_class.use(io) { |reader| reader.each_entry { |_, stream| data = stream.read } }

      expect(data).to eq("DATA")
    end

    it "prefers pax path over GNU long name when both are present" do
      io = build_gnu_and_pax_archive
      entry_name = nil

      described_class.use(io) { |reader| reader.each_entry { |entry, _| entry_name = entry.name } }

      expect(entry_name).to eq("pax_name.txt")
    end
  end

  describe "limits" do
    it "raises ArchiveLimitError when entry count exceeds limit" do
      expect {
        described_class.use(io, max_entry_count: 2) do |reader|
          reader.each_entry { |_, stream| stream.skip }
        end
      }.to raise_error(MiniTarball::ArchiveLimitError, /Entry count limit exceeded/)
    end

    it "raises ArchiveLimitError when file size exceeds limit" do
      expect {
        described_class.use(io, max_file_size: 100) do |reader|
          reader.each_entry { |_, stream| stream.skip }
        end
      }.to raise_error(MiniTarball::ArchiveLimitError, /Entry size limit exceeded/)
    end

    it "raises ArchiveLimitError when total size exceeds limit" do
      expect {
        described_class.use(io, max_total_size: 1000) do |reader|
          reader.each_entry { |_, stream| stream.skip }
        end
      }.to raise_error(MiniTarball::ArchiveLimitError, /Total size limit exceeded/)
    end

    it "allows disabling limits with nil" do
      expect {
        described_class.use(
          io,
          max_file_size: nil,
          max_total_size: nil,
          max_entry_count: nil,
        ) { |reader| reader.each_entry { |_, stream| stream.skip } }
      }.not_to raise_error
    end

    it "applies size limits to metadata entries" do
      long_name = "a" * 150 + ".txt"
      io = StringIO.new(String.new, "w+b")

      MiniTarball::Writer.use(io) { |writer| writer.file long_name, content: "data" }
      io.reopen(io.string, "rb")

      expect {
        described_class.use(io, max_file_size: 10) do |reader|
          reader.each_entry { |_, stream| stream.skip }
        end
      }.to raise_error(MiniTarball::ArchiveLimitError, /Entry size limit exceeded/)
    end

    it "rejects metadata entries larger than MAX_METADATA_SIZE" do
      io = StringIO.new(String.new, "w+b")
      header =
        MiniTarball::Header.new(
          name: "././@LongLink",
          size: MiniTarball::Reader::MAX_METADATA_SIZE + 1,
          typeflag: MiniTarball::Header::TYPE[:gnu_long_name],
          attrs: MiniTarball::EntryAttributes.with_file_defaults,
        )
      MiniTarball::HeaderWriter.new(io).write(header)
      io.rewind

      expect {
        described_class.use(io) { |reader| reader.each_entry { |_, stream| stream.skip } }
      }.to raise_error(MiniTarball::ArchiveLimitError, /Metadata entry too large/)
    end
  end

  describe "#closed?" do
    it "returns false for a new reader" do
      reader = described_class.new(io)
      expect(reader.closed?).to be false
    end

    it "returns true after close" do
      reader = described_class.new(io)
      reader.close

      expect(reader.closed?).to be true
    end
  end

  describe "#close" do
    it "is idempotent" do
      reader = described_class.new(io)
      reader.close

      expect { reader.close }.not_to raise_error
    end

    it "raises IOError when iterating after close" do
      reader = described_class.new(io)
      reader.close

      expect { reader.each_entry {} }.to raise_error(IOError, /closed/)
    end
  end

  describe "directory entries" do
    it "identifies directory entries" do
      io =
        build_custom_archive(
          name: "dir/",
          typeflag: MiniTarball::Header::TYPE[:directory],
          content: "",
        )

      has_directory = false
      described_class.use(io) do |reader|
        reader.each_entry { |entry, _| has_directory = true if entry.directory? }
      end

      expect(has_directory).to be true
    end
  end

  describe "symlink entries" do
    it "identifies symlink entries" do
      mixed_archive = fixture("archives/mixed_entries.tar")
      io = StringIO.new(mixed_archive)

      symlinks = []
      described_class.use(io) do |reader|
        reader.each_entry do |entry, _|
          symlinks << { name: entry.name, target: entry.linkname } if entry.symlink?
        end
      end

      expect(symlinks).to include(hash_including(name: "link.txt", target: "file.txt"))
    end
  end

  describe "hardlink entries" do
    it "identifies hardlink entries" do
      mixed_archive = fixture("archives/mixed_entries.tar")
      io = StringIO.new(mixed_archive)

      hardlinks = []
      described_class.use(io) do |reader|
        reader.each_entry do |entry, _|
          hardlinks << { name: entry.name, target: entry.linkname } if entry.hardlink?
        end
      end

      expect(hardlinks).to include(hash_including(name: "hardlink.txt", target: "file.txt"))
    end
  end

  describe "#extract_all" do
    let(:tmpdir) { Dir.mktmpdir("reader_extract_test") }

    after { FileUtils.rm_rf(tmpdir) }

    it "extracts files to destination" do
      io = StringIO.new(archive_data)

      described_class.use(io) do |reader|
        extracted = reader.extract_all(tmpdir)
        expect(extracted.length).to eq(3)
      end

      expect(File.exist?(File.join(tmpdir, "file1.txt"))).to be true
      expect(File.exist?(File.join(tmpdir, "file2.txt"))).to be true
      expect(File.exist?(File.join(tmpdir, "file3.txt"))).to be true
    end

    it "extracts file contents correctly" do
      io = StringIO.new(archive_data)

      described_class.use(io) { |reader| reader.extract_all(tmpdir) }

      content = File.read(File.join(tmpdir, "file1.txt"))
      expect(content).to start_with("aaaaaaaaaaaaaaaa")
    end

    it "preserves permissions by default" do
      io = StringIO.new(archive_data)

      described_class.use(io) { |reader| reader.extract_all(tmpdir) }

      mode = File.stat(File.join(tmpdir, "file1.txt")).mode & 0o7777
      expect(mode).to eq(0644)
    end

    it "preserves modification times by default" do
      io = StringIO.new(archive_data)

      described_class.use(io) { |reader| reader.extract_all(tmpdir) }

      mtime = File.mtime(File.join(tmpdir, "file1.txt"))
      expect(mtime.year).to eq(2021)
    end

    it "can skip permission preservation" do
      io = StringIO.new(archive_data)

      described_class.use(io) { |reader| reader.extract_all(tmpdir, preserve_permissions: false) }

      # File should still exist
      expect(File.exist?(File.join(tmpdir, "file1.txt"))).to be true
    end

    it "extracts symlinks" do
      mixed_archive = fixture("archives/mixed_entries.tar")
      io = StringIO.new(mixed_archive)

      described_class.use(io) { |reader| reader.extract_all(tmpdir) }

      link_path = File.join(tmpdir, "link.txt")
      expect(File.symlink?(link_path)).to be true
      expect(File.readlink(link_path)).to eq("file.txt")
    end

    it "extracts hardlinks" do
      mixed_archive = fixture("archives/mixed_entries.tar")
      io = StringIO.new(mixed_archive)

      described_class.use(io) { |reader| reader.extract_all(tmpdir) }

      file_path = File.join(tmpdir, "file.txt")
      hardlink_path = File.join(tmpdir, "hardlink.txt")

      expect(File.exist?(hardlink_path)).to be true
      # Hardlinks share the same inode
      expect(File.stat(file_path).ino).to eq(File.stat(hardlink_path).ino)
    end

    it "extracts unknown entry types as regular files" do
      io = build_custom_archive(name: "mystery.bin", typeflag: "Z", content: "abc")

      described_class.use(io) { |reader| reader.extract_all(tmpdir) }

      expect(File.read(File.join(tmpdir, "mystery.bin"))).to eq("abc")
    end

    it "supports before and after hooks" do
      io = StringIO.new(archive_data)
      before_seen = []
      after_seen = []

      described_class.use(io) do |reader|
        extracted =
          reader.extract_all(
            tmpdir,
            before:
              lambda do |entry, _path|
                before_seen << entry.name
                entry.name != "file2.txt"
              end,
            after: ->(entry, path) { after_seen << [entry.name, path] },
          )

        expect(extracted).to include(File.join(tmpdir, "file1.txt"))
        expect(extracted).to include(File.join(tmpdir, "file3.txt"))
        expect(extracted).not_to include(File.join(tmpdir, "file2.txt"))
      end

      expect(before_seen).to include("file2.txt")
      expect(after_seen.map(&:first)).not_to include("file2.txt")
    end

    it "raises Errno::ENOENT if destination doesn't exist" do
      io = StringIO.new(archive_data)

      expect {
        described_class.use(io) { |reader| reader.extract_all("/nonexistent/path") }
      }.to raise_error(Errno::ENOENT)
    end

    it "rejects symlink targets that escape through a previously extracted symlink" do
      io = StringIO.new(String.new, "w+b")
      attrs = MiniTarball::EntryAttributes.with_file_defaults
      symlink_type = MiniTarball::Header::TYPE[:symlink]

      # `l -> .` then `m -> l/../secret`: lexically l/../secret stays inside
      # the destination, but physically l/.. is the destination's parent
      write_entry(
        io,
        MiniTarball::Header.new(name: "l", typeflag: symlink_type, linkname: ".", attrs:),
        "",
      )
      write_entry(
        io,
        MiniTarball::Header.new(name: "m", typeflag: symlink_type, linkname: "l/../secret", attrs:),
        "",
      )
      io.write("\0" * MiniTarball::Header::END_OF_ARCHIVE_SIZE)
      io.rewind

      expect { described_class.use(io) { |reader| reader.extract_all(tmpdir) } }.to raise_error(
        MiniTarball::PathTraversalError,
        /escapes destination/,
      )
    end
  end

  describe "truncated archives" do
    it "raises TruncatedArchiveError on short header read" do
      io = StringIO.new("short")

      expect {
        described_class.use(io) { |reader| reader.each_entry { |_, stream| stream.skip } }
      }.to raise_error(MiniTarball::TruncatedArchiveError)
    end

    it "raises TruncatedArchiveError when end-of-archive block is missing" do
      io = StringIO.new("\0" * 512)

      expect {
        described_class.use(io) { |reader| reader.each_entry { |_, stream| stream.skip } }
      }.to raise_error(MiniTarball::TruncatedArchiveError)
    end

    it "raises TruncatedArchiveError when entry padding is incomplete" do
      io = build_custom_archive(name: "file.txt", content: "abc", pad: false, end_blocks: false)

      expect {
        described_class.use(io) { |reader| reader.each_entry { |_, stream| stream.read } }
      }.to raise_error(MiniTarball::TruncatedArchiveError)
    end
  end
end
