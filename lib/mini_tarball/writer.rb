# frozen_string_literal: true

require "etc"

module MiniTarball
  class Writer
    END_OF_TAR_BLOCK_SIZE = 1024

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
      @placeholders = []
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

      stat = File.stat(source_file_path)

      @header_writer.write(
        Header.new(
          name: name,
          size: stat.size,
          mode: mode || stat.mode,
          uid: uid || stat.uid,
          gid: gid || stat.gid,
          uname: uname || Etc.getpwuid(stat.uid).name,
          gname: gname || Etc.getgrgid(stat.gid).name,
          mtime: mtime || stat.mtime,
        ),
      )

      File.open(source_file_path, "rb") { |file| IO.copy_stream(file, @write_only_io) }

      write_padding
      nil
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

      header_start_position = @io.pos
      @header_writer.write(Header.new(name: name))

      file_start_position = @io.pos
      yield @write_only_io
      file_size = @io.pos - file_start_position
      write_padding

      @io.seek(header_start_position)
      @header_writer.write(
        Header.new(
          name: name,
          size: file_size,
          mode: mode,
          uid: uid,
          gid: gid,
          uname: uname,
          gname: gname,
          mtime: mtime || Time.now.utc,
        ),
      )

      @io.seek(0, IO::SEEK_END)
      nil
    end

    # :reek:DuplicateMethodCall { allow_calls: ['@io.pos'] }
    # :reek:TooManyStatements
    def add_file_placeholder(name:, file_size:)
      ensure_not_closed

      placeholder = {}
      placeholder[:header_start_position] = @io.pos
      @header_writer.write(Header.new(name: name, size: file_size))

      placeholder[:file_start_position] = @io.pos
      @io.write("\0" * file_size)
      placeholder[:file_size] = file_size

      write_padding

      @placeholders << placeholder
      @placeholders.size - 1
    end

    # :reek:TooManyStatements
    def with_placeholder(index)
      placeholder = @placeholders[index]
      raise ArgumentError.new("Placeholder not found") if !placeholder

      @io.seek(placeholder[:header_start_position])
      old_write_only_io = @write_only_io
      @write_only_io =
        PlaceholderStream.new(
          @io,
          start_position: placeholder[:file_start_position],
          file_size: placeholder[:file_size],
        )

      yield self

      @write_only_io = old_write_only_io
      @io.seek(0, IO::SEEK_END)

      nil
    end

    def closed?
      @closed
    end

    def close
      ensure_not_closed

      @io.write("\0" * END_OF_TAR_BLOCK_SIZE)
      @io.close
      @closed = true
    end

    # :reek:FeatureEnvy
    # :reek:ManualDispatch
    private def ensure_valid_io(io)
      unless io.respond_to?(:pos) && io.respond_to?(:write) && io.respond_to?(:close)
        raise "No IO object given"
      end
    end

    private def ensure_not_closed
      raise IOError.new("#{self.class} is closed") if closed?
    end

    private def write_padding
      padding_length = (Header::BLOCK_SIZE - @io.pos) % Header::BLOCK_SIZE
      @io.write("\0" * padding_length)
    end
  end
end
