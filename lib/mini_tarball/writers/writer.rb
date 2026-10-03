# frozen_string_literal: true

require "fcntl"

module MiniTarball
  # Creates GNU tar format archives with streaming support.
  #
  # Writer supports adding files, directories, symlinks, and hardlinks to tar archives.
  # It handles long filenames (>100 bytes) using GNU tar extensions and supports
  # both seekable and non-seekable IO streams.
  #
  # A writer is not thread-safe. Add entries one after another. Don't add an
  # entry, fill a placeholder or close the writer from inside a content block.
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

    APPEND_MODE_MESSAGE = "IO is in append mode, headers can't be rewritten"
    private_constant :APPEND_MODE_MESSAGE

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
      rescue Exception => block_error
        # Also catches Interrupt, so that a failing close can't replace it.
        error = block_error
        raise
      ensure
        begin
          writer.close
        rescue StandardError
          # #close keeps the IO open when it fails, so callers can fill missing
          # placeholders. That's not possible anymore after this method returns.
          io.close
          raise unless error
        end
      end
    end

    def initialize(io)
      ensure_valid_io!(io)

      @io = io
      # nil, :not_seekable or :append_mode
      @seek_problem = seek_problem(io)
      @write_only_io = WriteOnlyStream.new(@io)
      @header_writer = HeaderWriter.new(@write_only_io)
      @content_writer = ContentWriter.new(@io, @header_writer)
      @user_group_lookup = UserGroupLookup::Cache.new
      @placeholder_manager =
        PlaceholderManager.new(
          io: @io,
          header_writer: @header_writer,
          content_writer: @content_writer,
          lookup: @user_group_lookup,
          entry_guard: method(:write_checked_entry),
        )
      # :open, :writing while an entry is written, or :closed
      @state = :open
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
    # @example Reserve a fixed size, NUL-padding whatever the block leaves unwritten
    #   w.file "data.bin", size: 4096, allow_short_writes: true do |stream|
    #     stream.write(payload)
    #   end
    #
    # @param name [String] filename in the archive
    # @param from [String, Pathname, nil] path to source file on disk
    # @param content [String, nil] string content to write
    # @param size [Integer, nil] content size (required for non-seekable IO with block)
    # @param mode [Integer, nil] file permissions
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param uname [String, nil] owner username
    # @param gname [String, nil] group name
    # @param mtime [Time, Integer, nil] modification time
    # @param allow_short_writes [Boolean] NUL-pad instead of raising when a block
    #   writes fewer bytes than the declared size (only valid with size: and a block)
    # @return [self]
    # @raise [UnsafeNameError] if name contains path traversal or absolute paths
    # @raise [NotSeekableError] if size is omitted and the IO doesn't support seeking
    # @raise [ArgumentError] if size is negative, content source is invalid, or size doesn't match content
    # @raise [WriteOutOfRangeError] if streamed content exceeds the declared size
    # @raise [IncompleteWriteError] if streamed content is smaller than the declared size
    # @raise [FileChangedError] if the +from:+ file changes its size while it is copied
    #   and allow_short_writes is false
    # @raise [ValueTooLargeError] if numeric values exceed tar header limits
    # @raise [IOError] if the writer is closed or another entry is still being written
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
      allow_short_writes: false,
      &block
    )
      ensure_writable!
      name = validated_name(name)
      ensure_valid_size!(size) if size
      ensure_valid_short_write_opt!(allow_short_writes:, size:, block:)

      write_entry do
        ContentSource.open(
          from:,
          content:,
          block:,
          lookup: @user_group_lookup,
          mode:,
          uid:,
          gid:,
          uname:,
          gname:,
          mtime:,
        ) do |source|
          label = from ? "file" : "content"
          write_file_entry(name, source, declared_size: size, allow_short_writes:, label:)
        end
      end

      self
    end

    # Adds a directory entry to the archive.
    # A trailing slash is automatically appended to the name if not present.
    #
    # @param name [String] the directory name in the archive
    # @param mode [Integer, nil] directory permissions (default: 0755)
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param uname [String, nil] owner username (default: "nobody")
    # @param gname [String, nil] group name (default: "nogroup")
    # @param mtime [Time, Integer, nil] modification time (default: current time)
    # @return [self]
    # @raise [UnsafeNameError] if name contains path traversal or absolute paths
    # @raise [ValueTooLargeError] if numeric values exceed tar header limits
    # @raise [IOError] if the writer is closed or another entry is still being written
    def directory(name, mode: nil, uid: nil, gid: nil, uname: nil, gname: nil, mtime: nil)
      ensure_writable!
      name = validated_name(name, directory: true)
      name = "#{name}/" unless name.end_with?("/")

      attrs =
        EntryAttributes.with_defaults(default_mode: 0755, mode:, uid:, gid:, uname:, gname:, mtime:)
      @header_writer.write(Header.new(name:, typeflag: Header::TYPE_DIRECTORY, attrs:))
      self
    end

    # Adds a symbolic link entry to the archive.
    #
    # @param name [String] the symlink name in the archive
    # @param target [String] the path the symlink points to (must be relative)
    # @param mode [Integer, nil] permissions (default: 0777)
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param uname [String, nil] owner username (default: "nobody")
    # @param gname [String, nil] group name (default: "nogroup")
    # @param mtime [Time, Integer, nil] modification time (default: current time)
    # @param allow_parent_references [Boolean] allow .. in target path (default: false for security)
    # @return [self]
    # @raise [UnsafeNameError] if name or target contains absolute paths or path traversal
    # @raise [ValueTooLargeError] if numeric values exceed tar header limits
    # @raise [IOError] if the writer is closed or another entry is still being written
    def symlink(
      name,
      target:,
      mode: nil,
      uid: nil,
      gid: nil,
      uname: nil,
      gname: nil,
      mtime: nil,
      allow_parent_references: false
    )
      write_link(
        name:,
        target:,
        typeflag: Header::TYPE_SYMLINK,
        default_mode: 0777,
        allow_parent_references:,
        mode:,
        uid:,
        gid:,
        uname:,
        gname:,
        mtime:,
      )
    end

    # Adds a hard link entry to the archive.
    #
    # @param name [String] the link name in the archive
    # @param target [String] the path to the existing file (must be relative)
    # @param mode [Integer, nil] permissions (default: 0644)
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param uname [String, nil] owner username (default: "nobody")
    # @param gname [String, nil] group name (default: "nogroup")
    # @param mtime [Time, Integer, nil] modification time (default: current time)
    # @return [self]
    # @raise [UnsafeNameError] if name or target contains absolute paths or path traversal.
    #   Hardlink targets are names of entries in the archive, so +..+ is never allowed.
    # @raise [ValueTooLargeError] if numeric values exceed tar header limits
    # @raise [IOError] if the writer is closed or another entry is still being written
    def hardlink(name, target:, mode: nil, uid: nil, gid: nil, uname: nil, gname: nil, mtime: nil)
      write_link(
        name:,
        target:,
        typeflag: Header::TYPE_HARDLINK,
        default_mode: 0644,
        mode:,
        uid:,
        gid:,
        uname:,
        gname:,
        mtime:,
      )
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
    # @raise [IOError] if the writer is closed or another entry is still being written
    def placeholder(name, size:)
      ensure_writable!
      ensure_seekable_io!
      name = validated_name(name)
      ensure_valid_size!(size)

      @placeholder_manager.reserve(name:, size:)
    end

    # @return [Boolean]
    def closed?
      @state == :closed
    end

    # Closes the writer, writing the end-of-archive marker.
    # The underlying IO is also closed.
    # Calling close on an already-closed writer is a no-op.
    #
    # Unfilled placeholders are checked before anything is written or closed,
    # so a caller can rescue the error, fill them, and close again.
    #
    # @return [void]
    # @raise [UnfilledPlaceholderError] if any placeholders remain unfilled
    # @raise [IOError] if another entry is still being written
    def close
      return if closed?
      ensure_writable!
      ensure_all_placeholders_filled!

      begin
        NullWriter.write(@io, END_OF_TAR_BLOCK_SIZE)
      ensure
        @state = :closed
        @io.close
      end
    end

    private

    def write_file_entry(name, source, declared_size:, allow_short_writes:, label:)
      known_size = source.size
      if known_size
        ensure_matching_size!(expected: declared_size, actual: known_size, label:)
      elsif !declared_size
        ensure_seekable_io!
        return write_file_seekable(name, source)
      end

      @content_writer.write_file(
        name:,
        size: known_size || declared_size,
        attrs: source.attrs,
        allow_short_writes:,
      ) { |stream| source.write_to(stream) }
    end

    # Streams content of unknown size, then seeks back and rewrites the header
    # with the real size.
    def write_file_seekable(name, source)
      header_start = @io.pos
      # Uses the real attributes, so invalid ones raise before any content is
      # written. Only the size changes later.
      content_start = header_start + @header_writer.write(Header.new(name:, attrs: source.attrs))

      begin
        source.write_to(@write_only_io)
      ensure
        content_size = @io.pos - content_start
        @content_writer.write_padding(content_size)

        begin
          @io.seek(header_start)
          written = @header_writer.write(Header.new(name:, size: content_size, attrs: source.attrs))
          ensure_header_rewritten!(header_start + written)
        ensure
          @io.seek(0, IO::SEEK_END)
        end
      end
    end

    def write_link(
      name:,
      target:,
      typeflag:,
      default_mode:,
      allow_parent_references: false,
      **attribute_overrides
    )
      ensure_writable!
      name = validated_name(name)
      PathValidator.validate_target!(target, allow_parent_references:)
      attrs = EntryAttributes.with_defaults(default_mode:, **attribute_overrides)

      @header_writer.write(Header.new(name:, typeflag:, linkname: target, attrs:))

      self
    end

    def ensure_valid_io!(io)
      unless io.respond_to?(:pos) && io.respond_to?(:write) && io.respond_to?(:close)
        raise NoIOLikeObjectError
      end
    end

    def ensure_seekable_io!
      case @seek_problem
      when :not_seekable
        raise NotSeekableError
      when :append_mode
        raise NotSeekableError, APPEND_MODE_MESSAGE
      end
    end

    def seek_problem(io)
      return :not_seekable unless seekable?(io)
      :append_mode if append_mode?(io)
    end

    # Pipes and sockets respond to seek but fail when called, so try it once.
    def seekable?(io)
      return false unless io.respond_to?(:seek)

      io.seek(0, IO::SEEK_CUR)
      true
    rescue SystemCallError, NotImplementedError
      false
    end

    # In append mode, every write goes to the end of the file, even after a seek.
    def append_mode?(io)
      return false unless io.respond_to?(:fcntl)

      io.fcntl(Fcntl::F_GETFL).anybits?(Fcntl::O_APPEND)
    rescue SystemCallError, NotImplementedError, ArgumentError
      # TruffleRuby's StringIO has a fcntl that takes no arguments
      false
    end

    # Some IO wrappers don't move when seek is called. The header would then
    # end up after the content.
    def ensure_header_rewritten!(expected_pos)
      pos = @io.pos
      return if pos == expected_pos

      raise NotSeekableError,
            "IO did not seek to the header, so it can't be rewritten " \
              "(expected position #{expected_pos}, got #{pos})"
    end

    def ensure_writable!
      return if @state == :open
      raise IOError, "Another entry is still being written" if @state == :writing
      raise IOError, "#{self.class} is closed"
    end

    # Placeholder fills use this, so a nested call is rejected no matter which
    # kind of entry is being written.
    def write_checked_entry(&)
      ensure_writable!
      write_entry(&)
    end

    # Call ensure_writable! before this.
    def write_entry
      @state = :writing
      begin
        yield
      ensure
        @state = :open
      end
    end

    # Returns a frozen copy, so changing the caller's string later can't change
    # the name. Placeholders and streamed files use the name again after user
    # code ran.
    #
    # Only directory names may end with "/". Extractors treat such entries as
    # directories, so a file named "foo/" would lose its content.
    def validated_name(name, directory: false)
      PathValidator.validate_name!(name)
      if !directory && name.end_with?("/")
        raise UnsafeNameError, "Only directory names may end with '/': #{name}"
      end

      -name
    end

    def ensure_valid_size!(size)
      unless size.instance_of?(Integer)
        raise ArgumentError, "Size must be an Integer, got #{size.class}"
      end
      raise ArgumentError, "Size must be non-negative" if size < 0
    end

    def ensure_matching_size!(expected:, actual:, label:)
      return unless expected
      return if expected == actual
      raise ArgumentError, "Size #{expected} does not match #{label} size #{actual}"
    end

    def ensure_valid_short_write_opt!(allow_short_writes:, size:, block:)
      return unless allow_short_writes
      return if size && block

      raise ArgumentError, "allow_short_writes requires size: and a block"
    end

    def ensure_all_placeholders_filled!
      raise UnfilledPlaceholderError unless @placeholder_manager.all_filled?
    end
  end
end
