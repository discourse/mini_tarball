# frozen_string_literal: true

require "etc"

module MiniTarball
  class NoIOLikeObjectError < StandardError
    def initialize(msg = "IO object is not valid")
      super
    end
  end

  class NotSeekableError < StandardError
    def initialize(msg = "IO object is not seekable")
      super
    end
  end

  class UnsafeNameError < StandardError
  end

  class LinkTargetTooLongError < StandardError
    def initialize(msg = "Link target exceeds 100 bytes")
      super
    end
  end

  class UnfilledPlaceholderError < StandardError
    def initialize(msg = "Unfilled placeholders remain")
      super
    end
  end

  class Writer
    END_OF_TAR_BLOCK_SIZE = 1024
    NULL_BLOCK = ("\0" * END_OF_TAR_BLOCK_SIZE).freeze
    DEFAULT_UNAME = "nobody"
    DEFAULT_GNAME = "nogroup"
    private_constant :END_OF_TAR_BLOCK_SIZE, :NULL_BLOCK, :DEFAULT_UNAME, :DEFAULT_GNAME

    # @param [String] filename
    # @yieldparam [Writer]
    #
    # :reek:NestedIterators
    def self.create(filename)
      File.open(filename, "wb") { |file| use(file) { |writer| yield(writer) } }
    end

    # @param [IO] io
    # @yieldparam [Writer]
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

    # :reek:ControlParameter
    # :reek:DuplicateMethodCall { allow_calls: ['stat.uid', 'stat.gid'] }
    # :reek:FeatureEnvy
    # :reek:LongParameterList
    # :reek:TooManyStatements
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
          uname: uname || lookup_username(stat.uid),
          gname: gname || lookup_groupname(stat.gid),
          mtime: mtime || stat.mtime,
        ),
      )

      File.open(source_file_path, "rb") { |file| IO.copy_stream(file, @write_only_io) }

      write_padding
      self
    end

    # :reek:LongParameterList
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

    # :reek:LongParameterList
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
      ensure_not_closed
      ensure_safe_name(name)
      ensure_valid_link_target(target)

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
          typeflag: Header::TYPE_SYMLINK,
          linkname: target,
        ),
      )

      self
    end

    # :reek:LongParameterList
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
      ensure_not_closed
      ensure_safe_name(name)
      ensure_valid_link_target(target)

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
          typeflag: Header::TYPE_HARDLINK,
          linkname: target,
        ),
      )

      self
    end

    # Adds a file by streaming content from a block.
    #
    # @param name [String] The filename in the archive
    # @param size [Integer, nil] Expected content size. Required for non-seekable IO (e.g., gzip).
    #   If omitted, the IO must be seekable so the size can be determined after writing.
    #
    # @note When +size+ is provided, it MUST match the actual bytes written. If fewer bytes
    #   are written, the remainder is filled with NUL bytes. When the archive is later read
    #   or extracted, the declared size is used - there is no way to distinguish padding from
    #   intentional content. This affects both streaming (e.g., S3 uploads include the padding)
    #   and disk extraction (extracted files will have the declared size, not actual content size).
    #
    # @example With seekable IO (size determined automatically)
    #   writer.add_file_from_stream(name: "test.txt") { |s| s.write("hello") }
    #
    # @example With non-seekable IO (gzip) - size must be exact
    #   content = "hello"
    #   writer.add_file_from_stream(name: "test.txt", size: content.bytesize) do |s|
    #     s.write(content)
    #   end
    #
    # :reek:ControlParameter
    # :reek:DuplicateMethodCall { allow_calls: ['@io.pos'] }
    # :reek:LongParameterList
    # :reek:TooManyStatements
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
    # @param name [String] The filename in the archive
    # @param size [Integer] Reserved size in bytes
    # @return [PlaceholderRef] A data object representing the reservation
    #
    # @note The +size+ declares the maximum content. If less is written when filling,
    #   the remainder stays as NUL bytes. See {#add_file_from_stream} for implications.
    #
    # @note All reservations must be filled before closing the writer.
    #
    # :reek:DuplicateMethodCall { allow_calls: ['@io.pos'] }
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

      yield self

      @write_only_io = old_write_only_io
      @io.seek(0, IO::SEEK_END)
    end

    # :reek:LongParameterList
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

      @io.write(NULL_BLOCK.byteslice(0, capped_stream.remaining)) if capped_stream.remaining > 0
      write_padding
    end

    # :reek:DuplicateMethodCall { allow_calls: ['@io.pos'] }
    # :reek:LongParameterList
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

    def closed?
      @closed
    end

    def close
      ensure_not_closed
      ensure_all_placeholders_filled!

      @io.write(NULL_BLOCK)
      @io.close
      @closed = true
    end

    # :reek:FeatureEnvy
    # :reek:ManualDispatch
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
      @io.write(NULL_BLOCK.byteslice(0, padding_length)) if padding_length > 0
    end

    private def ensure_safe_name(name)
      raise UnsafeNameError, "Absolute paths are not allowed: #{name}" if name.start_with?("/")

      if name.start_with?("../") || name.end_with?("/..") || name.include?("/../")
        raise UnsafeNameError, "Path traversal is not allowed: #{name}"
      end
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

    private def ensure_valid_link_target(target)
      max_length = Header::FIELDS[:linkname][:length]
      raise LinkTargetTooLongError if target.bytesize > max_length
    end

    private def lookup_username(uid)
      Etc.getpwuid(uid).name
    rescue ArgumentError
      DEFAULT_UNAME
    end

    private def lookup_groupname(gid)
      Etc.getgrgid(gid).name
    rescue ArgumentError
      DEFAULT_GNAME
    end
  end
end
