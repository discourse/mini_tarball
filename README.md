# MiniTarball

This is a **minimal** implementation of the [GNU Tar format](https://www.gnu.org/software/tar/manual/html_chapter/tar_15.html) in Ruby.

#### 👍 Supported features
* Writing tar files
* Adding files with
  * unlimited file size
  * unlimited file name length
* Unicode file names
* Works with streams, so you don't need to waste disk space by creating temporary files

#### 👎 Currently not supported features
* Reading tar files
* Adding hardlinks, symlinks or directories
* Other features of GNU tar like sparse files
* Creating POSIX.1-2001 (pax) archives or any other tar format

## Installation

Add this line to your application's Gemfile:

``` ruby
gem 'mini_tarball'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install mini_tarball

## Usage

### Create a `MiniTarball::Writer`
There are multiple ways for creating a `MiniTarball::Writer`:

1. Use an existing IO-like stream.
   ``` ruby
   io =  File.open(archive_path, "wb")
   MiniTarball::Writer.use(io) do |writer|
     # add files by calling writer.add_file or writer.add_file_from_stream
   end
   ```

2. Create a new file by supplying a file name.
   ``` ruby
   MiniTarball::Writer.create(filename) do |writer|
     # add files by calling writer.add_file or writer.add_file_from_stream
   end
   ```

3. Create it manually. You need to close the writer when you are done in order finalize the tar file.
   ``` ruby
   writer = MiniTarball::Writer.new(io)
   # add files by calling writer.add_file or writer.add_file_from_stream
   writer.close
   ```

### Adding files

You can add existing files as well as write a stream into the tar file.

#### Adding existing files
You can add existing files by calling `MiniTarball::Writer#add_file`. The required `name` argument can be a file name or a complete path.

``` ruby
writer.add_file(name: "file1.txt", source_file_path: "/home/foo/file1.txt")
```

By default the file's attributes are stored in the tar file, but you can override them by supplying values for the optional arguments (`mode`, `uname`, `gname`, `uid`, `gid`, `mtime`) to `MiniTarball::Writer#add_file`.

#### Adding files from a stream
You can add files of unknown size by calling `MiniTarball::Writer#add_file_from_stream`. The required `name` argument can be a file name or a complete path.

> 💡 This method doesn't work with non-seekable streams like `Zlib::GzipWriter`.

Here are some examples:

* Use IO.copy_stream to efficiently copy a stream into the tar
   ``` ruby
   File.open("/home/foo/file1.txt", "rb") do |input_stream|
     writer.add_file_from_stream(name: "file1.txt") do |output_stream|
       IO.copy_stream(input_stream, output_stream)
     end
   end
   ```

* Directly write into the output stream
   ``` ruby
   writer.add_file_from_stream(name: "foo/bar/file2.txt") do |output_stream|
     output_stream.write("Hello world!")
   end
   ```

`MiniTarball::Writer#add_file_from_stream` has multiple optional arguments:

|Argument|Default|Description|
|:---|:---|:---|
|mode|`0644`|Permission and mode bits|
|uname|`"nobody"`|User name of file owner|
|gname|`"nogroup"`|Group name of file owner|
|uid|`nil`|User ID of file owner|
|gid|`nil`|Group ID of file owner|
|mtime|`Time.now.utc`|Modification time|

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

To release a new version, update the version number in `version.rb`, and then push it to GitHub. This will automatically create a tag and publish the gem on [rubygems.org](https://rubygems.org).

## Contributing

Pull requests are welcome on GitHub at https://github.com/discourse/mini_tarball.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
