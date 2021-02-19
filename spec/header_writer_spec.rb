# frozen_string_literal: true

require 'time'

RSpec.describe MiniTarball::HeaderWriter do
  describe "#write" do
    let(:io) { StringIO.new.binmode }
    subject { MiniTarball::HeaderWriter.new(io) }

    let!(:default_options) do
      {
        mode: 0644,
        mtime: Time.parse("2021-02-15T20:11:34Z"),
        uname: "discourse",
        gname: "www-data",
        uid: 1001,
        gid: 33
      }
    end

    it "correctly outputs header for small file" do
      header = MiniTarball::Header.new(name: "small_file", size: 536_870_913, **default_options)
      subject.write(header)
      expect(io.string).to eq(fixture("headers/small_file_header"))
    end

    it "correctly outputs header for large file" do
      header = MiniTarball::Header.new(name: "large_file", size: 10_737_418_241, **default_options)
      subject.write(header)
      expect(io.string).to eq(fixture("headers/large_file_header"))
    end

    it "correctly outputs header for file with long name" do
      header = MiniTarball::Header.new(name: "this_is_an_extremely_long_file_name_with_many_underscores_and_" \
        "lots_of_ascii_characters_in_it_and_will_be_used_to_test_gnu_tar.txt", size: 4, **default_options)
      subject.write(header)
      expect(io.string).to eq(fixture("headers/long_filename_header"))
    end

    it "correctly outputs header for file with Unicode name" do
      header = MiniTarball::Header.new(name: "这是一个测试.txt", size: 4, **default_options)
      subject.write(header)
      expect(io.string).to eq(fixture("headers/unicode_filename_header"))
    end

    it "correctly outputs header for file with long Unicode name" do
      header = MiniTarball::Header.new(
        name: "这是一个很长的中文句子，用于测试我们的实现在计算文件名长度时是否使用字节大小.txt",
        size: 4,
        **default_options
      )
      subject.write(header)
      expect(io.string).to eq(fixture("headers/long_unicode_filename_header"))
    end

    it "correctly outputs header for file stored in short path" do
      header = MiniTarball::Header.new(name: "this/is/a/short/path/test.txt", size: 4, **default_options)
      subject.write(header)
      expect(io.string).to eq(fixture("headers/short_path_header"))
    end

    it "correctly outputs header for file stored in long path" do
      header = MiniTarball::Header.new(name: "this/is/a/very/long/path/with/lots/of/sub/directories/to/test/" \
        "how/gnu/tar/behaves/when/files/are/stored/in/a/very/long/path/test.txt", size: 4, **default_options)
      subject.write(header)
      expect(io.string).to eq(fixture("headers/long_path_header"))
    end
  end
end
