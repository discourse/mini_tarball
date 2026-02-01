# MiniTarball

This is a **minimal** implementation of
the [GNU Tar format](https://www.gnu.org/software/tar/manual/html_chapter/Tar-Internals.html) in
Ruby.

#### Supported features

* Writing tar files
* Adding files, directories, symlinks, and hardlinks
* Very large file sizes and file name lengths (within tar format limits)
* Unicode file names
* Works with streams, including non-seekable streams like `Zlib::GzipWriter`
* Path traversal protection
* No temporary files needed

#### Currently not supported features

* Reading tar files
* Sparse files
* POSIX.1-2001 (pax) archives or other tar formats

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
   io = File.open(archive_path, "wb")
   MiniTarball::Writer.use(io) do |w|
     w.file "hello.txt", content: "Hello, world!"
   end
   ```

2. Create a new file by supplying a file name.
   ``` ruby
   MiniTarball::Writer.create(filename) do |w|
     w.file "hello.txt", content: "Hello, world!"
   end
   ```

3. Create it manually. You need to close the writer when you are done in order to finalize the tar
   file.
   ``` ruby
   writer = MiniTarball::Writer.new(io)
   writer.file "hello.txt", content: "Hello, world!"
   writer.close
   ```

### Add files

The `file` method adds a file entry to the archive. You must provide exactly one content source:

- `from:` - copy from a file on disk
- `content:` - write a string directly
- A block - stream content

#### Copy from disk

``` ruby
# Copy a file (attributes read from disk)
w.file "README.md", from: "README.md"

# Copy with a different archive name
w.file "config.json", from: "config/production.json"

# Override file attributes
w.file "script.sh", from: "script.sh", mode: 0755
```

When using `from:`, file attributes (mode, uid, gid, uname, gname, mtime) are read from the source
file by default. You can override any of them.

#### Write string content

``` ruby
w.file "VERSION", content: "1.0.0"
w.file "data.json", content: JSON.generate(users: [...])
```

When using `content:`, default attributes are used (mode: 0644, uname: "nobody", gname: "nogroup").

#### Stream content

``` ruby
# Stream into the archive (requires seekable IO)
w.file "report.csv" do |stream|
  records.each { |record| stream.write(record.to_csv) }
end
```

For non-seekable streams like `Zlib::GzipWriter`, see [Streaming with Gzip](#streaming-with-gzip).

#### File attributes

All content sources accept the same optional attributes:

| Argument | Default                              | Description              |
|:---------|:-------------------------------------|:-------------------------|
| mode     | `0644` (or from file with `from:`)   | Permission and mode bits |
| uname    | `"nobody"` (or from file)            | User name of file owner  |
| gname    | `"nogroup"` (or from file)           | Group name of file owner |
| uid      | `nil` (or from file)                 | User ID of file owner    |
| gid      | `nil` (or from file)                 | Group ID of file owner   |
| mtime    | `Time.now.utc` (or from file)        | Modification time        |

### Reserve and fill placeholders

Placeholders allow you to reserve space for a file within the tar. This is useful when you want to
store a file at the beginning of the archive but don't know the content until you've added other
files.

> **Note:** Placeholders require a seekable stream. They cannot be used with non-seekable streams
> like `Zlib::GzipWriter`.

``` ruby
MiniTarball::Writer.create("archive.tar") do |w|
  # Reserve space at the beginning
  manifest = w.placeholder "manifest.json", size: 4096

  # Add files, collecting metadata
  files = []
  Dir.glob("data/*.csv").each do |path|
    name = File.basename(path)
    w.file "data/#{name}", from: path
    files << name
  end

  # Fill the placeholder with collected info
  manifest.fill content: JSON.generate(files: files)
end
```

The `placeholder` method returns a `Placeholder` object. Use it to fill the reserved entry later;
it does not expose the reserved name or size. Fill it using the same options as `file`:

``` ruby
# Fill from string
manifest.fill content: json_data

# Fill from file
manifest.fill from: "generated_manifest.json"

# Fill via streaming
manifest.fill do |stream|
  stream.write(generated_content)
end
```

The filename and size are fixed when calling `placeholder`. You can set attributes (mode, uname,
gname, uid, gid, mtime) when filling.

The writer fills unused space with null characters if the actual content is smaller than the
reserved `size`. Writing more content than `size` raises `MiniTarball::WriteOutOfRangeError`.

All placeholders must be filled before closing the writer, or `MiniTarball::UnfilledPlaceholderError`
is raised.

### Add directories

``` ruby
w.directory "my_folder"
w.directory "nested/path/to/folder", mode: 0700
```

A trailing slash is automatically appended if not present.

### Add symlinks and hardlinks

``` ruby
# Symlink
w.symlink "link.txt", target: "original.txt"

# Hardlink (target must already exist in archive)
w.hardlink "copy.txt", target: "original.txt"
```

By default, targets containing `..` are rejected to prevent path traversal attacks. Use
`allow_parent_references: true` if you need to create links with parent directory references:

``` ruby
w.symlink "docs/latest", target: "../releases/v1.0", allow_parent_references: true
```

### Streaming with Gzip

When writing to non-seekable streams like `Zlib::GzipWriter`, you must provide the `size:` parameter
for streamed content:

``` ruby
require "zlib"

Zlib::GzipWriter.open("archive.tar.gz") do |gzip|
  MiniTarball::Writer.use(gzip) do |w|
    json_data = { users: [...] }.to_json

    w.file "data.json", size: json_data.bytesize do |stream|
      stream.write(json_data)
    end
  end
end
```

Using `content:` works without `size:` since the size is known:

``` ruby
Zlib::GzipWriter.open("archive.tar.gz") do |gzip|
  MiniTarball::Writer.use(gzip) do |w|
    w.file "data.json", content: json_data
  end
end
```

If the exact size is unknown, you can provide a maximum size. Any unused space will be padded with
null bytes (which compress extremely well):

``` ruby
w.file "export.csv", size: 1024 * 1024 do |stream|
  records.each { |record| stream.write(record.to_csv) }
  # Remaining space automatically padded with NULs
end
```

## Error classes

| Error                      | Description                                                   |
|:---------------------------|:--------------------------------------------------------------|
| `UnsafeNameError`          | Entry name contains path traversal or absolute paths          |
| `WriteOutOfRangeError`     | Write exceeds declared size (placeholder or streamed)         |
| `UnfilledPlaceholderError` | Writer closed with unfilled placeholders                      |
| `NotSeekableError`         | Operation requires seekable IO but stream is not seekable     |
| `NoIOLikeObjectError`      | Provided object doesn't respond to required IO methods        |
| `ValueTooLargeError`       | Numeric value exceeds tar header field capacity               |

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run
the tests. You can also run `bin/console` for an interactive prompt that will allow you to
experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

To release a new version, update the version number in `version.rb`, and then push it to GitHub.
This will automatically create a tag and publish the gem on [rubygems.org](https://rubygems.org).

On MacOS you need to run `brew install gnu-tar`, otherwise some specs will fail.

### RubyCritic

You can run `SimpleCov` and `RubyCritic` by executing the following:

```
COVERAGE=1 rake spec && rubycritic --no-browser
```

## Contributing

Pull requests are welcome on GitHub at https://github.com/discourse/mini_tarball.

## License

The gem is available as open source under the terms of
the [MIT License](https://opensource.org/licenses/MIT).
