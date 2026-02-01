# frozen_string_literal: true

module MiniTarball
  # Creates GNU tar format archives with streaming support.
  #
  # Writer supports adding files, directories, symlinks, and hardlinks to tar archives.
  # It handles long filenames (>100 bytes) using GNU tar extensions and supports
  # both seekable and non-seekable IO streams.
  #
  # @example Creating an archive from files
  #   Writer.create("archive.tar") do |w|
  #     w.file "README.md", from: "README.md"
  #     w.file "config.json", from: "config/prod.json", mode: 0600
  #     w.directory "lib/"
  #   end
  #
  # @example Writing content directly
  #   Writer.create("archive.tar") do |w|
  #     w.file "VERSION", content: "1.0.0"
  #     w.file "data.json", content: JSON.generate(data)
  #   end
  #
  # @example Streaming content
  #   Writer.create("archive.tar") do |w|
  #     w.file "report.csv" do |stream|
  #       rows.each { |row| stream.write(row.to_csv) }
  #     end
  #   end
  #
  # @example Using placeholders for deferred content
  #   Writer.create("archive.tar") do |w|
  #     manifest = w.placeholder "manifest.json", size: 4096
  #     w.file "data.bin", from: "data.bin"
  #     manifest.fill content: JSON.generate(files: ["data.bin"])
  #   end
  class Writer
    END_OF_TAR_BLOCK_SIZE = 1024
    private_constant :END_OF_TAR_BLOCK_SIZE

    # Creates a new tar file and yields a writer for adding entries.
    # The file is automatically closed when the block returns.
    #
    # @param filename [String] path to the tar file to create
    # @yieldparam writer [Writer] the writer instance
    # @return [void]
    def self.create(filename)
      File.open(filename, "wb") { |file| use(file) { |writer| yield(writer) } }
    end

    # Wraps an IO object and yields a writer for adding entries.
    # The writer is automatically closed when the block returns.
    #
    # @param io [IO] an IO-like object supporting +pos+, +write+, and +close+
    # @yieldparam writer [Writer] the writer instance
    # @return [void]
    def self.use(io)
      writer = new(io)
      error = nil

      begin
        yield(writer)
      rescue => block_error
        error = block_error
        raise
      ensure
        begin
          writer.close
        rescue => close_error
          raise close_error unless error
        end
      end

      nil
    end

    def initialize(io)
      ensure_valid_io!(io)

      @io = io
      @write_only_io = WriteOnlyStream.new(@io)
      @header_writer = HeaderWriter.new(@write_only_io)
      @content_writer = ContentWriter.new(@io, @header_writer)
      @placeholder_manager = PlaceholderManager.new(@io, @header_writer, @content_writer)
      @closed = false
    end

    # Adds a file entry to the archive.
    #
    # Exactly one content source must be provided:
    # - +from:+ to copy from a file on disk
    # - +content:+ to write a string directly
    # - A block to stream content
    #
    # @example Copy from disk
    #   w.file "README.md", from: "README.md"
    #   w.file "config.json", from: "config/prod.json", mode: 0600
    #
    # @example Write string content
    #   w.file "VERSION", content: "1.0.0"
    #   w.file "data.json", content: JSON.generate(data)
    #
    # @example Stream content (seekable IO)
    #   w.file "report.csv" do |stream|
    #     rows.each { |row| stream.write(row.to_csv) }
    #   end
    #
    # @example Stream content (non-seekable IO like gzip - size required)
    #   w.file "data.bin", size: data.bytesize do |stream|
    #     stream.write(data)
    #   end
    #
    # @param name [String] filename in the archive
    # @param from [String, nil] path to source file on disk
    # @param content [String, nil] string content to write
    # @param size [Integer, nil] content size (required for non-seekable IO with block)
    # @param mode [Integer, nil] file permissions
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param uname [String, nil] owner username
    # @param gname [String, nil] group name
    # @param mtime [Time, nil] modification time
    # @return [self]
    # @raise [UnsafeNameError] if name contains path traversal or absolute paths
    # @raise [NotSeekableError] if size is omitted and the IO doesn't support seeking
    # @raise [ArgumentError] if size is negative, content source is invalid, or size doesn't match content
    # @raise [WriteOutOfRangeError] if streamed content exceeds the declared size
    # @raise [ValueTooLargeError] if numeric values exceed tar header limits
    def file(
      name,
      from: nil,
      content: nil,
      size: nil,
      mode: nil,
      uid: nil,
      gid: nil,
      uname: nil,
      gname: nil,
      mtime: nil,
      &block
    )
      ensure_not_closed!
      ensure_safe_name!(name)
      ensure_valid_size!(size) if size
      SourceValidator.validate!(from, content, block)

      if from
        attribute_overrides = EntryAttributes.new(mode:, uid:, gid:, uname:, gname:, mtime:)
        write_file_from_disk(name, from, expected_size: size, attribute_overrides:)
        return self
      end

      attrs = EntryAttributes.with_file_defaults(mode:, uid:, gid:, uname:, gname:, mtime:)

      if content
        content_size = content.bytesize
        ensure_matching_size!(expected: size, actual: content_size, label: "content")
        @content_writer.write_file(name, content_size, attrs) { |stream| stream.write(content) }
      elsif size
        @content_writer.write_file(name, size, attrs, &block)
      else
        ensure_seekable_io!
        write_file_seekable(name, attrs, &block)
      end

      self
    end

    # Adds a directory entry to the archive.
    # A trailing slash is automatically appended to the name if not present.
    #
    # @param name [String] the directory name in the archive
    # @param mode [Integer] directory permissions (default: 0755)
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param uname [String] owner username (default: "nobody")
    # @param gname [String] group name (default: "nogroup")
    # @param mtime [Time, nil] modification time (default: current time)
    # @return [self]
    # @raise [UnsafeNameError] if name contains path traversal or absolute paths
    # @raise [ValueTooLargeError] if numeric values exceed tar header limits
    def directory(
      name,
      mode: 0755,
      uid: nil,
      gid: nil,
      uname: "nobody",
      gname: "nogroup",
      mtime: nil
    )
      ensure_not_closed!
      ensure_safe_name!(name)
      name = "#{name}/" unless name.end_with?("/")

      attrs = EntryAttributes.new(mode:, uid:, gid:, uname:, gname:, mtime:)
      @header_writer.write(Header.new(name:, size: 0, typeflag: Header::TYPE_DIRECTORY, attrs:))
      self
    end

    # Adds a symbolic link entry to the archive.
    #
    # @param name [String] the symlink name in the archive
    # @param target [String] the path the symlink points to (must be relative)
    # @param mode [Integer] permissions (default: 0777)
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param uname [String] owner username (default: "nobody")
    # @param gname [String] group name (default: "nogroup")
    # @param mtime [Time, nil] modification time (default: current time)
    # @param allow_parent_references [Boolean] allow .. in target path (default: false for security)
    # @return [self]
    # @raise [UnsafeNameError] if name or target contains absolute paths or path traversal
    # @raise [ValueTooLargeError] if numeric values exceed tar header limits
    def symlink(
      name,
      target:,
      mode: 0777,
      uid: nil,
      gid: nil,
      uname: "nobody",
      gname: "nogroup",
      mtime: nil,
      allow_parent_references: false
    )
      attrs = EntryAttributes.new(mode:, uid:, gid:, uname:, gname:, mtime:)
      write_link(name:, target:, typeflag: Header::TYPE_SYMLINK, attrs:, allow_parent_references:)
    end

    # Adds a hard link entry to the archive.
    #
    # @param name [String] the link name in the archive
    # @param target [String] the path to the existing file (must be relative)
    # @param mode [Integer] permissions (default: 0644)
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param uname [String] owner username (default: "nobody")
    # @param gname [String] group name (default: "nogroup")
    # @param mtime [Time, nil] modification time (default: current time)
    # @param allow_parent_references [Boolean] allow .. in target path (default: false for security)
    # @return [self]
    # @raise [UnsafeNameError] if name or target contains absolute paths or path traversal
    # @raise [ValueTooLargeError] if numeric values exceed tar header limits
    def hardlink(
      name,
      target:,
      mode: 0644,
      uid: nil,
      gid: nil,
      uname: "nobody",
      gname: "nogroup",
      mtime: nil,
      allow_parent_references: false
    )
      attrs = EntryAttributes.new(mode:, uid:, gid:, uname:, gname:, mtime:)
      write_link(name:, target:, typeflag: Header::TYPE_HARDLINK, attrs:, allow_parent_references:)
    end

    # Reserves space for a file to be filled later.
    #
    # Returns a {Placeholder} object that can be filled via {Placeholder#fill}.
    # This is useful when file content isn't available yet but position in archive matters.
    #
    # @example
    #   manifest = w.placeholder "manifest.json", size: 4096
    #   w.file "data.bin", from: "data.bin"
    #   manifest.fill content: JSON.generate(files: ["data.bin"])
    #
    # @param name [String] the filename in the archive
    # @param size [Integer] reserved size in bytes
    # @return [Placeholder] a placeholder object to fill later
    # @raise [UnsafeNameError] if name contains path traversal or absolute paths
    # @raise [NotSeekableError] if the IO doesn't support seeking
    # @raise [ArgumentError] if size is negative
    # @raise [ValueTooLargeError] if size exceeds tar header limits
    def placeholder(name, size:)
      ensure_not_closed!
      ensure_seekable_io!
      ensure_safe_name!(name)
      ensure_valid_size!(size)

      @placeholder_manager.reserve(name:, size:)
    end

    # Returns whether the writer has been closed.
    # @return [Boolean]
    def closed?
      @closed
    end

    # Closes the writer, writing the end-of-archive marker.
    # The underlying IO is also closed.
    # Calling close on an already-closed writer is a no-op.
    #
    # @return [void]
    # @raise [UnfilledPlaceholderError] if any placeholders remain unfilled
    def close
      return if closed?
      ensure_all_placeholders_filled!

      NullWriter.write(@io, END_OF_TAR_BLOCK_SIZE)
      nil
    ensure
      @io.close unless @closed
      @closed = true
    end

    private

    # Opens file once, uses fstat for attributes and size, then copies content.
    # This avoids race conditions where the file could change between stat and read.
    def write_file_from_disk(name, path, expected_size:, attribute_overrides:)
      File.open(path, "rb") do |file|
        stat = file.stat
        file_size = stat.size
        ensure_matching_size!(expected: expected_size, actual: file_size, label: "file")

        attrs = EntryAttributes.from_stat(stat, **attribute_overrides.to_h)
        @content_writer.write_file(name, file_size, attrs) { |stream| IO.copy_stream(file, stream) }
      end
    end

    def write_file_seekable(name, attrs, &block)
      header_start_position = @io.pos
      @header_writer.write(Header.new(name:))

      file_start_position = @io.pos

      begin
        block.call(@write_only_io)
      ensure
        file_end_position = @io.pos
        file_size = file_end_position - file_start_position
        @content_writer.write_padding

        @io.seek(header_start_position)
        @header_writer.write(Header.new(name:, size: file_size, attrs:))

        @io.seek(0, IO::SEEK_END)
      end
    end

    def write_link(name:, target:, typeflag:, attrs:, allow_parent_references: false)
      ensure_not_closed!
      ensure_safe_name!(name)
      ensure_safe_target!(target, allow_parent_references:)

      @header_writer.write(Header.new(name:, size: 0, typeflag:, linkname: target, attrs:))

      self
    end

    def ensure_valid_io!(io)
      unless io.respond_to?(:pos) && io.respond_to?(:write) && io.respond_to?(:close)
        raise NoIOLikeObjectError
      end
    end

    def ensure_seekable_io!
      raise NotSeekableError unless @io.respond_to?(:seek)
    end

    def ensure_not_closed!
      raise IOError.new("#{self.class} is closed") if closed?
    end

    def ensure_safe_name!(name)
      PathValidator.validate_name!(name)
    end

    def ensure_valid_size!(size)
      raise ArgumentError, "Size must be non-negative" if size < 0
    end

    def ensure_matching_size!(expected:, actual:, label: "content")
      return unless expected
      return if expected == actual
      raise ArgumentError, "Size #{expected} does not match #{label} size #{actual}"
    end

    def ensure_safe_target!(target, allow_parent_references:)
      PathValidator.validate_target!(target, allow_parent_references:)
    end

    def ensure_all_placeholders_filled!
      raise UnfilledPlaceholderError unless @placeholder_manager.all_filled?
    end
  end
end
