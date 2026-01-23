# frozen_string_literal: true

module MiniTarball
  class Entry
    attr_reader :name, :size, :mode, :uid, :gid, :mtime, :uname, :gname, :typeflag, :linkname

    def initialize(header_values)
      @name = header_values[:name]
      @size = header_values[:size]
      @mode = header_values[:mode]
      @uid = header_values[:uid]
      @gid = header_values[:gid]
      @mtime = header_values[:mtime] ? Time.at(header_values[:mtime]) : nil
      @uname = header_values[:uname]
      @gname = header_values[:gname]
      @typeflag = header_values[:typeflag]
      @linkname = header_values[:linkname]
    end

    def file?
      typeflag == "0" || typeflag == "" || typeflag.nil?
    end

    def directory?
      typeflag == "5"
    end

    def symlink?
      typeflag == "2"
    end

    def hardlink?
      typeflag == "1"
    end
  end
end
