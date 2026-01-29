# frozen_string_literal: true

module MiniTarball
  # Creates GNU tar format archives with streaming support.
  #
  # Writer supports adding files, directories, symlinks, and hardlinks to tar archives.
  # It handles long filenames (>100 bytes) using GNU tar extensions and supports
  # both seekable and non-seekable IO streams.
  #
  # @example Creating an archive from files
  #   Writer.create("archive.tar") do |writer|
  #     writer.add_file(name: "README.md", source_file_path: "README.md")
  #     writer.add_directory(name: "lib/")
  #   end
  #
  # @example Streaming content without a file
  #   Writer.use(io) do |writer|
  #     writer.add_file_from_stream(name: "hello.txt") do |stream|
  #       stream.write("Hello, world!")
  #     end
  #   end
  #
  # @example Using placeholders for deferred content
  #   Writer.create("archive.tar") do |writer|
  #     placeholder = writer.reserve(name: "manifest.json", size: 1024)
  #     writer.add_file(name: "data.bin", source_file_path: "data.bin")
  #     writer.fill(placeholder) do |filler|
  #       filler.add_file_from_stream(name: "manifest.json") { |s| s.write(json) }
  #     end
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

      begin
        yield(writer)
      ensure
        writer.close
      end

      nil
    end

    def initialize(io)
      ensure_valid_io(io)

      @io = io
      @write_only_io = WriteOnlyStream.new(@io)
      @header_writer = HeaderWriter.new(@write_only_io)
      @closed = false
      @writer_id = Object.new
      @placeholders = {}
    end

    # Adds a file from the filesystem to the archive.
    # File metadata (mode, owner, timestamps) is read from the source file
    # unless explicitly overridden.
    #
    # @param name [String] the filename in the archive
    # @param source_file_path [String] path to the source file on disk
    # @param mode [Integer, nil] file permissions (default: from source file)
    # @param uname [String, nil] owner username (default: from source file)
    # @param gname [String, nil] group name (default: from source file)
    # @param uid [Integer, nil] owner user ID (default: from source file)
    # @param gid [Integer, nil] group ID (default: from source file)
    # @param mtime [Time, nil] modification time (default: from source file)
    # @return [self]
    # @raise [UnsafeNameError] if name contains path traversal or absolute paths
    def add_file(
      name:,
      source_file_path:,
      mode: nil,
      uname: nil,
      gname: nil,
      uid: nil,
      gid: nil,
      mtime: nil
    )
      ensure_not_closed
      ensure_safe_name(name)

      stat = File.stat(source_file_path)

      @header_writer.write(
        Header.new(
          name:,
          size: stat.size,
          mode: mode || stat.mode,
          uid: uid || stat.uid,
          gid: gid || stat.gid,
          uname: uname || UserGroupLookup.username(stat.uid),
          gname: gname || UserGroupLookup.groupname(stat.gid),
          mtime: mtime || stat.mtime,
        ),
      )

      File.open(source_file_path, "rb") { |file| IO.copy_stream(file, @write_only_io) }

      write_padding
      self
    end

    # Adds a directory entry to the archive.
    # A trailing slash is automatically appended to the name if not present.
    #
    # @param name [String] the directory name in the archive
    # @param mode [Integer] directory permissions (default: 0755)
    # @param uname [String] owner username (default: "nobody")
    # @param gname [String] group name (default: "nogroup")
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param mtime [Time, nil] modification time (default: current time)
    # @return [self]
    # @raise [UnsafeNameError] if name contains path traversal or absolute paths
    def add_directory(
      name:,
      mode: 0755,
      uname: "nobody",
      gname: "nogroup",
      uid: nil,
      gid: nil,
      mtime: nil
    )
      ensure_not_closed
      name = "#{name}/" unless name.end_with?("/")
      ensure_safe_name(name)

      @header_writer.write(
        Header.new(
          name:,
          size: 0,
          mode:,
          uid:,
          gid:,
          uname:,
          gname:,
          mtime: mtime || Time.now.utc,
          typeflag: Header::TYPE_DIRECTORY,
        ),
      )

      self
    end

    # Adds a symbolic link entry to the archive.
    #
    # @param name [String] the symlink name in the archive
    # @param target [String] the path the symlink points to (must be relative)
    # @param mode [Integer] permissions (default: 0777)
    # @param uname [String] owner username (default: "nobody")
    # @param gname [String] group name (default: "nogroup")
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param mtime [Time, nil] modification time (default: current time)
    # @return [self]
    # @raise [UnsafeNameError] if name or target contains absolute paths
    def add_symlink(
      name:,
      target:,
      mode: 0777,
      uname: "nobody",
      gname: "nogroup",
      uid: nil,
      gid: nil,
      mtime: nil
    )
      add_link(
        name:,
        target:,
        typeflag: Header::TYPE_SYMLINK,
        mode:,
        uname:,
        gname:,
        uid:,
        gid:,
        mtime:,
      )
    end

    # Adds a hard link entry to the archive.
    #
    # @param name [String] the link name in the archive
    # @param target [String] the path to the existing file (must be relative)
    # @param mode [Integer] permissions (default: 0644)
    # @param uname [String] owner username (default: "nobody")
    # @param gname [String] group name (default: "nogroup")
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param mtime [Time, nil] modification time (default: current time)
    # @return [self]
    # @raise [UnsafeNameError] if name or target contains absolute paths
    def add_hardlink(
      name:,
      target:,
      mode: 0644,
      uname: "nobody",
      gname: "nogroup",
      uid: nil,
      gid: nil,
      mtime: nil
    )
      add_link(
        name:,
        target:,
        typeflag: Header::TYPE_HARDLINK,
        mode:,
        uname:,
        gname:,
        uid:,
        gid:,
        mtime:,
      )
    end

    private def add_link(name:, target:, typeflag:, mode:, uname:, gname:, uid:, gid:, mtime:)
      ensure_not_closed
      ensure_safe_name(name)
      ensure_safe_target(target)

      @header_writer.write(
        Header.new(
          name:,
          size: 0,
          mode:,
          uid:,
          gid:,
          uname:,
          gname:,
          mtime: mtime || Time.now.utc,
          typeflag:,
          linkname: target,
        ),
      )

      self
    end

    # Adds a file by streaming content from a block.
    #
    # @param name [String] the filename in the archive
    # @param size [Integer, nil] expected content size (required for non-seekable IO)
    # @param mode [Integer] file permissions (default: 0644)
    # @param uname [String] owner username (default: "nobody")
    # @param gname [String] group name (default: "nogroup")
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param mtime [Time, nil] modification time (default: current time)
    # @yieldparam stream [IO] a stream to write file content to
    # @return [self]
    # @raise [UnsafeNameError] if name contains path traversal or absolute paths
    # @raise [NotSeekableError] if size is omitted and the IO doesn't support seeking
    #
    # @note When +size+ is provided, it MUST match the actual bytes written. If fewer
    #   bytes are written, the remainder is filled with NUL bytes. The declared size
    #   is used when extracting - there is no way to distinguish padding from content.
    #
    # @example With seekable IO (size determined automatically)
    #   writer.add_file_from_stream(name: "test.txt") { |s| s.write("hello") }
    #
    # @example With non-seekable IO (gzip) - size must be exact
    #   content = "hello"
    #   writer.add_file_from_stream(name: "test.txt", size: content.bytesize) do |s|
    #     s.write(content)
    #   end
    def add_file_from_stream(
      name:,
      size: nil,
      mode: 0644,
      uname: "nobody",
      gname: "nogroup",
      uid: nil,
      gid: nil,
      mtime: nil,
      &block
    )
      ensure_not_closed
      ensure_safe_name(name)

      if size
        add_file_from_stream_with_size(
          name:,
          size:,
          mode:,
          uname:,
          gname:,
          uid:,
          gid:,
          mtime:,
          &block
        )
      else
        ensure_seekable_io
        add_file_from_stream_seekable(name:, mode:, uname:, gname:, uid:, gid:, mtime:, &block)
      end

      self
    end

    # Reserves space for a file to be filled later.
    # Useful when file content isn't available yet but position in archive matters.
    #
    # @param name [String] the filename in the archive
    # @param size [Integer] reserved size in bytes
    # @return [PlaceholderRef] a reference to pass to {#fill}
    # @raise [UnsafeNameError] if name contains path traversal or absolute paths
    #
    # @note The +size+ declares the maximum content. If less is written when filling,
    #   the remainder stays as NUL bytes. See {#add_file_from_stream} for implications.
    # @note All reservations must be filled before closing the writer.
    #
    # @see #fill
    def reserve(name:, size:)
      ensure_not_closed
      ensure_safe_name(name)

      header_start_position = @io.pos
      @header_writer.write(Header.new(name:, size:))

      file_start_position = @io.pos
      @io.write("\0" * size)

      write_padding

      placeholder =
        PlaceholderRef.new(
          header_start_position:,
          file_start_position:,
          size:,
          writer_id: @writer_id,
        )
      @placeholders[placeholder] = :unfilled
      placeholder
    end

    # Fills a previously reserved placeholder with content.
    # Yields a {PlaceholderFiller} that provides a restricted interface
    # for adding files within the reserved space.
    #
    # @param placeholder [PlaceholderRef] the placeholder returned by {#reserve}
    # @yieldparam filler [PlaceholderFiller] restricted writer for the placeholder
    # @return [self]
    # @raise [ArgumentError] if placeholder is unknown, already filled, or from another writer
    # @raise [NotSeekableError] if the IO doesn't support seeking
    # @see #reserve
    def fill(placeholder, &block)
      ensure_not_closed
      ensure_seekable_io
      validate_placeholder!(placeholder)

      fill_placeholder(placeholder, &block)
      @placeholders[placeholder] = :filled
      self
    end

    private def fill_placeholder(placeholder)
      @io.seek(placeholder.header_start_position)
      old_write_only_io = @write_only_io
      @write_only_io =
        PlaceholderStream.new(
          @io,
          start_position: placeholder.file_start_position,
          size: placeholder.size,
        )

      yield PlaceholderFiller.new(self)

      @write_only_io = old_write_only_io
      @io.seek(0, IO::SEEK_END)
    end

    private def add_file_from_stream_with_size(
      name:,
      size:,
      mode:,
      uname:,
      gname:,
      uid:,
      gid:,
      mtime:
    )
      @header_writer.write(
        Header.new(name:, size:, mode:, uid:, gid:, uname:, gname:, mtime: mtime || Time.now.utc),
      )

      capped_stream = CappedWriteStream.new(@io, max_size: size)
      yield capped_stream

      @io.write("\0" * capped_stream.remaining) if capped_stream.remaining > 0
      write_padding
    end

    private def add_file_from_stream_seekable(name:, mode:, uname:, gname:, uid:, gid:, mtime:)
      header_start_position = @io.pos
      @header_writer.write(Header.new(name:))

      file_start_position = @io.pos
      yield @write_only_io
      file_size = @io.pos - file_start_position
      write_padding

      @io.seek(header_start_position)
      @header_writer.write(
        Header.new(
          name:,
          size: file_size,
          mode:,
          uid:,
          gid:,
          uname:,
          gname:,
          mtime: mtime || Time.now.utc,
        ),
      )

      @io.seek(0, IO::SEEK_END)
    end

    # Returns whether the writer has been closed.
    # @return [Boolean]
    def closed?
      @closed
    end

    # Closes the writer, writing the end-of-archive marker.
    # The underlying IO is also closed.
    #
    # @return [void]
    # @raise [UnfilledPlaceholderError] if any placeholders remain unfilled
    # @raise [IOError] if the writer is already closed
    def close
      ensure_not_closed
      ensure_all_placeholders_filled!

      @io.write("\0" * END_OF_TAR_BLOCK_SIZE)
      @io.close
      @closed = true
    end

    private def ensure_valid_io(io)
      unless io.respond_to?(:pos) && io.respond_to?(:write) && io.respond_to?(:close)
        raise NoIOLikeObjectError
      end
    end

    private def ensure_seekable_io
      raise NotSeekableError unless @io.respond_to?(:seek)
    end

    private def ensure_not_closed
      raise IOError.new("#{self.class} is closed") if closed?
    end

    private def write_padding
      padding_length = (Header::BLOCK_SIZE - @io.pos) % Header::BLOCK_SIZE
      @io.write("\0" * padding_length) if padding_length > 0
    end

    private def ensure_safe_name(name)
      PathValidator.validate_name!(name)
    end

    private def ensure_safe_target(target)
      PathValidator.validate_target!(target)
    end

    private def validate_placeholder!(placeholder)
      state = @placeholders[placeholder]
      raise ArgumentError, "Unknown placeholder" if state.nil?
      raise ArgumentError, "Placeholder already filled" if state == :filled

      unless placeholder.writer_id == @writer_id
        raise ArgumentError, "Placeholder belongs to another writer"
      end
    end

    private def ensure_all_placeholders_filled!
      unfilled = @placeholders.values.include?(:unfilled)
      return unless unfilled

      @io.close
      @closed = true
      raise UnfilledPlaceholderError
    end
  end
end
