# frozen_string_literal: true

require "time"

RSpec.describe MiniTarball::HeaderWriter do
  describe "#write" do
    subject(:header_writer) { MiniTarball::HeaderWriter.new(io) }

    let(:io) { StringIO.new.binmode }

    let(:default_attrs) do
      MiniTarball::EntryAttributes.new(
        mode: 0644,
        uid: 1001,
        gid: 33,
        uname: "discourse",
        gname: "www-data",
        mtime: Time.parse("2021-02-15T20:11:34Z"),
      )
    end

    it "correctly outputs header for small file" do
      header = MiniTarball::Header.new(name: "small_file", size: 536_870_913, attrs: default_attrs)
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/small_file_header"))
    end

    it "correctly outputs header for large file" do
      header =
        MiniTarball::Header.new(name: "large_file", size: 10_737_418_241, attrs: default_attrs)
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/large_file_header"))
    end

    it "correctly outputs header for file with long name" do
      header =
        MiniTarball::Header.new(
          name:
            "this_is_an_extremely_long_file_name_with_many_underscores_and_" \
              "lots_of_ascii_characters_in_it_and_will_be_used_to_test_gnu_tar.txt",
          size: 3,
          attrs: default_attrs,
        )
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/long_filename_header"))
    end

    it "correctly outputs header for file with Unicode name" do
      header = MiniTarball::Header.new(name: "这是一个测试.txt", size: 3, attrs: default_attrs)
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/unicode_filename_header"))
    end

    it "correctly outputs header for file with long Unicode name" do
      header =
        MiniTarball::Header.new(
          name: "这是一个很长的中文句子，用于测试我们的实现在计算文件名长度时是否使用字节大小.txt",
          size: 3,
          attrs: default_attrs,
        )
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/long_unicode_filename_header"))
    end

    it "correctly outputs header for file stored in short path" do
      header =
        MiniTarball::Header.new(
          name: "this/is/a/short/path/test.txt",
          size: 3,
          attrs: default_attrs,
        )
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/short_path_header"))
    end

    it "correctly outputs header for file stored in long path" do
      header =
        MiniTarball::Header.new(
          name:
            "this/is/a/very/long/path/with/lots/of/sub/directories/to/test/" \
              "how/gnu/tar/behaves/when/files/are/stored/in/a/very/long/path/test.txt",
          size: 3,
          attrs: default_attrs,
        )
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/long_path_header"))
    end

    it "ignores file type bitfields" do
      attrs_with_file_type =
        MiniTarball::EntryAttributes.new(
          mode: 0100644,
          uid: 1001,
          gid: 33,
          uname: "discourse",
          gname: "www-data",
          mtime: Time.parse("2021-02-15T20:11:34Z"),
        )
      header =
        MiniTarball::Header.new(name: "small_file", size: 536_870_913, attrs: attrs_with_file_type)
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/small_file_header"))
    end

    it "correctly outputs header for directory" do
      dir_attrs =
        MiniTarball::EntryAttributes.new(
          mode: 0755,
          uid: 1001,
          gid: 33,
          uname: "discourse",
          gname: "www-data",
          mtime: Time.parse("2021-02-15T20:11:34Z"),
        )
      header =
        MiniTarball::Header.new(
          name: "testdir/",
          size: 0,
          typeflag: MiniTarball::Header::TYPE_DIRECTORY,
          attrs: dir_attrs,
        )
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/directory_header"))
    end

    it "correctly outputs header for symlink with short target" do
      header =
        MiniTarball::Header.new(
          name: "link.txt",
          size: 0,
          typeflag: MiniTarball::Header::TYPE_SYMLINK,
          linkname: "target.txt",
          attrs: default_attrs,
        )
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/symlink_short_target_header"))
    end

    it "correctly outputs header for symlink with long target" do
      long_target =
        "this/is/a/very/long/path/with/lots/of/sub/directories/to/test/how/gnu/tar/" \
          "behaves/when/symlinks/point/to/a/very/long/target/path.txt"
      header =
        MiniTarball::Header.new(
          name: "link.txt",
          size: 0,
          typeflag: MiniTarball::Header::TYPE_SYMLINK,
          linkname: long_target,
          attrs: default_attrs,
        )
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/symlink_long_target_header"))
    end

    it "correctly outputs header for hardlink with short target" do
      header =
        MiniTarball::Header.new(
          name: "hardlink.txt",
          size: 0,
          typeflag: MiniTarball::Header::TYPE_HARDLINK,
          linkname: "original.txt",
          attrs: default_attrs,
        )
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/hardlink_short_target_header"))
    end

    it "correctly outputs header for hardlink with long target" do
      long_name =
        "this_is_an_extremely_long_file_name_with_many_underscores_and_" \
          "lots_of_ascii_characters_that_exceeds_one_hundred_bytes.txt"
      header =
        MiniTarball::Header.new(
          name: "hardlink.txt",
          size: 0,
          typeflag: MiniTarball::Header::TYPE_HARDLINK,
          linkname: long_name,
          attrs: default_attrs,
        )
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/hardlink_long_target_header"))
    end

    it "correctly outputs header for exactly 100 byte name (no extension needed)" do
      name = "a" * 96 + ".txt"
      header = MiniTarball::Header.new(name:, size: 3, attrs: default_attrs)
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/exactly_100_byte_name_header"))
    end

    it "correctly outputs header for exactly 101 byte name (extension required)" do
      name = "a" * 97 + ".txt"
      header = MiniTarball::Header.new(name:, size: 3, attrs: default_attrs)
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/exactly_101_byte_name_header"))
    end

    it "correctly outputs header for empty file" do
      header = MiniTarball::Header.new(name: "empty.txt", size: 0, attrs: default_attrs)
      header_writer.write(header)
      expect(io.string).to eq(fixture("headers/empty_file_header"))
    end
  end
end
