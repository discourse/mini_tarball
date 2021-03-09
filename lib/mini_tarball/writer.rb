# frozen_string_literal: true

require 'etc'

module MiniTarball
  class Writer
    END_OF_TAR_BLOCK_SIZE = 1024

    # @param [String] filename
    # @yieldparam [Writer]
    def self.create(filename)
      File.open(filename, "wb") do |file|
        use(file) { |writer| yield(writer) }
      end
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
      ensure_valid_io!(io)

      @io = io
      @write_only_io = WriteOnlyStream.new(@io)
      @header_writer = HeaderWriter.new(@write_only_io)
      @closed = false
    end

    def add_file(name:, source_file_path:, mode: nil, uname: nil, gname: nil, uid: nil, gid: nil, mtime: nil)
      ensure_not_closed!

      file = File.open(source_file_path, "rb")
      stat = File.stat(source_file_path)

      @header_writer.write(Header.new(
        name: name,
        size: stat.size,
        mode: mode || stat.mode,
        uid: uid || stat.uid,
        gid: gid || stat.gid,
        uname: uname || Etc.getpwuid(stat.uid).name,
        gname: gname || Etc.getgrgid(stat.gid).name,
        mtime: mtime || stat.mtime
      ))

      IO.copy_stream(file, @write_only_io)
      write_padding
      nil
    end

    def add_file_from_stream(name:, mode: 0644, uname: "nobody", gname: "nogroup", uid: nil, gid: nil, mtime: nil)
      ensure_not_closed!

      header_start_position = @io.pos
      @header_writer.write(Header.new(name: name))

      file_start_position = @io.pos
      yield @write_only_io
      file_size = @io.pos - file_start_position
      write_padding

      @io.seek(header_start_position)
      @header_writer.write(Header.new(
        name: name,
        size: file_size,
        mode: mode,
        uid: uid,
        gid: gid,
        uname: uname,
        gname: gname,
        mtime: mtime || Time.now.utc
      ))

      @io.seek(0, IO::SEEK_END)
      nil
    end

    def closed?
      @closed
    end

    def close
      ensure_not_closed!

      @io.write("\0" * END_OF_TAR_BLOCK_SIZE)
      @io.close
      @closed = true
    end

    private

    def ensure_valid_io!(io)
      raise "No IO object given" unless io.respond_to?(:pos) &&
        io.respond_to?(:write) && io.respond_to?(:close)
    end

    def ensure_not_closed!
      raise IOError.new("#{self.class} is closed") if closed?
    end

    def write_padding
      padding_length = (Header::BLOCK_SIZE - @io.pos) % Header::BLOCK_SIZE
      @io.write("\0" * padding_length)
    end
  end
end
