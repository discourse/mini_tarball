#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'tempfile'

def create_tar(output_filename:, filenames:, uname: "discourse", uid: 1001, gname: "www-data",
               gid: 33, mtime: "2021-02-15T20:11:34Z", blocking_factor: nil, announce: false)

  print "Creating #{File.basename(output_filename)}..." if announce

  filenames = filenames.join(" ")
  options = +"--format=gnu --owner=#{uname}:#{uid} --group=#{gname}:#{gid} --mtime='#{mtime}' --mode=0644"
  options << " --blocking-factor=#{blocking_factor}" if blocking_factor

  tar_binary = /darwin/ =~ RUBY_PLATFORM ? "gtar" : "tar"
  `#{tar_binary} #{options} -cf #{output_filename} #{filenames}`

  puts "done" if announce
end

def create_tar_header(name:, header_size:)
  tar_filename = "#{name}.tar"
  tar_header_filename = "#{name}_header"
  print "Creating #{tar_header_filename}... "

  filenames = []
  yield(filenames, name)

  create_tar(output_filename: tar_filename, filenames: filenames)

  `dd if=#{tar_filename} count=1 bs=#{header_size} of=#{tar_header_filename} status=none`

  filenames.map! { |f| f.split(File::SEPARATOR).first }
  filenames << tar_filename
  FileUtils.rm_rf(filenames)

  puts "done"
end

def create_file(filename:, content: nil, filesize: nil, path: nil)
  if path
    FileUtils.mkdir_p(path)
    path = File.join(path, filename)
  else
    path = filename
  end

  if filesize
    `fallocate -l #{filesize} #{path}`
  elsif content
    File.open(path, "w") { |f| f.write content }
  end

  path
end

def create_content(length:)
  index = 0
  content = +""
  chars = ("a".."z").to_a

  while index < length / 16
    content << chars[index % chars.size] * 16
    index += 1
  end

  if (remainder = length % 16) > 0
    content << chars[index % chars.size] * remainder
  end

  content << "\n"
  content
end

# Directories
FileUtils.mkdir_p(%w{archives files headers})

# Headers
Dir.chdir(File.expand_path("headers", __dir__)) do
  create_tar_header(name: "small_file", header_size: 512) do |filenames, name|
    filenames << create_file(filename: name, filesize: 536_870_913)
  end

  create_tar_header(name: "large_file", header_size: 512) do |filenames, name|
    filenames << create_file(filename: name, filesize: 10_737_418_241)
  end

  create_tar_header(name: "long_filename", header_size: 1536) do |filenames, _|
    filenames << create_file(
      filename: "this_is_an_extremely_long_file_name_with_many_underscores_and_" \
        "lots_of_ascii_characters_in_it_and_will_be_used_to_test_gnu_tar.txt",
      content: "foo"
    )
  end

  create_tar_header(name: "unicode_filename", header_size: 512) do |filenames, _|
    filenames << create_file(filename: "这是一个测试.txt", content: "foo")
  end

  create_tar_header(name: "long_unicode_filename", header_size: 1536) do |filenames, _|
    filenames << create_file(
      filename: "这是一个很长的中文句子，用于测试我们的实现在计算文件名长度时是否使用字节大小.txt",
      content: "foo"
    )
  end

  create_tar_header(name: "short_path", header_size: 512) do |filenames, _|
    filenames << create_file(filename: "test.txt", path: "this/is/a/short/path", content: "foo")
  end

  create_tar_header(name: "long_path", header_size: 1536) do |filenames, _|
    filenames << create_file(
      filename: "test.txt",
      path: "this/is/a/very/long/path/with/lots/of/sub/directories/to/test/how/gnu/tar/" \
        "behaves/when/files/are/stored/in/a/very/long/path",
      content: "foo"
    )
  end
end

# Files
archives_path = File.expand_path("archives", __dir__)
Dir.chdir(File.expand_path("files", __dir__)) do
  print "Creating files..."
  create_file(filename: "file1.txt", content: create_content(length: 1042))
  create_file(filename: "file2.txt", content: create_content(length: 391))
  create_file(filename: "file3.txt", content: create_content(length: 1063))
  create_file(filename: "file1_with_trailing_zeros.txt", content: create_content(length: 1042) + "\0" * 1492)
  puts "done"

  create_tar(
    output_filename: File.join(archives_path, "multiple_files.tar"),
    filenames: %w{file1.txt file2.txt file3.txt},
    blocking_factor: 1,
    announce: true
  )

  Dir.mktmpdir do |temp_dir|
    FileUtils.copy_file("file1_with_trailing_zeros.txt", File.join(temp_dir, "file1.txt"), true)
    FileUtils.copy_file("file2.txt", File.join(temp_dir, "file2.txt"), true)

    Dir.chdir(temp_dir) do
      create_tar(
        output_filename: File.join(archives_path, "small_file_in_large_placeholder.tar"),
        filenames: %w{file1.txt file2.txt},
        blocking_factor: 1,
        announce: true
      )
    end
  end
end
