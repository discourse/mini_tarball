# frozen_string_literal: true

require "etc"

module MiniTarball
  class NoIOLikeObjectError < StandardError
  end

  class UnsafeNameError < StandardError
  end

  class Writer
    END_OF_TAR_BLOCK_SIZE = 1024
    NULL_BLOCK = ("\0" * END_OF_TAR_BLOCK_SIZE).freeze
    DEFAULT_UNAME = "nobody"
    DEFAULT_GNAME = "nogroup"

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

    # :reek:ControlParameter
    # :reek:DuplicateMethodCall { allow_calls: ['@io.pos'] }
    # :reek:LongParameterList
    # :reek:TooManyStatements
    def add_file_from_stream(
      name:,
      mode: 0644,
      uname: "nobody",
      gname: "nogroup",
      uid: nil,
      gid: nil,
      mtime: nil
    )
      ensure_not_closed
      ensure_seekable_io
      ensure_safe_name(name)

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
      self
    end

    # :reek:DuplicateMethodCall { allow_calls: ['@io.pos'] }
    def add_file_placeholder(name:, size:)
      ensure_not_closed
      ensure_safe_name(name)

      header_start_position = @io.pos
      @header_writer.write(Header.new(name:, size:))

      file_start_position = @io.pos
      @io.write("\0" * size)

      write_padding

      Placeholder.new(writer: self, header_start_position:, file_start_position:, size:)
    end

    private def fill_placeholder(placeholder)
      ensure_seekable_io

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

    def closed?
      @closed
    end

    def close
      ensure_not_closed

      @io.write(NULL_BLOCK)
      @io.close
      @closed = true
    end

    # :reek:FeatureEnvy
    # :reek:ManualDispatch
    private def ensure_valid_io(io)
      unless io.respond_to?(:pos) && io.respond_to?(:write) && io.respond_to?(:close)
        raise NoIOLikeObjectError.new("No IO object given")
      end
    end

    private def ensure_seekable_io
      raise NoIOLikeObjectError.new("No seekable IO object given") unless @io.respond_to?(:seek)
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
