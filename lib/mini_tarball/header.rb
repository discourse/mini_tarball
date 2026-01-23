# frozen_string_literal: true

module MiniTarball
  class Header
    # Size of each block in the tar file in bytes
    BLOCK_SIZE = 512 # bytes

    TYPE_REGULAR = "0"
    TYPE_LONG_LINK = "L"

    # stree-ignore
    FIELDS = {
      name:     { length: 100, type: :chars }.freeze,
      mode:     { length:   8, type: :mode }.freeze,
      uid:      { length:   8, type: :number }.freeze,
      gid:      { length:   8, type: :number }.freeze,
      size:     { length:  12, type: :number }.freeze,
      mtime:    { length:  12, type: :number }.freeze,
      checksum: { length:   8, type: :checksum }.freeze,
      typeflag: { length:   1, type: :chars }.freeze,
      linkname: { length: 100, type: :chars }.freeze,
      magic:    { length:   6, type: :chars }.freeze,
      version:  { length:   2, type: :chars }.freeze,
      uname:    { length:  32, type: :chars }.freeze,
      gname:    { length:  32, type: :chars }.freeze,
      devmajor: { length:   8, type: :number }.freeze,
      devminor: { length:   8, type: :number }.freeze,
      prefix:   { length: 155, type: :chars }.freeze,
    }.freeze

    def self.long_link_header(name)
      Header.new(
        name: "././@LongLink",
        mode: 0644,
        uid: 0,
        gid: 0,
        size: name.bytesize + 1,
        typeflag: TYPE_LONG_LINK,
        uname: "root",
        gname: "root",
      )
    end

    # :reek:LongParameterList
    def initialize(
      name:,
      mode: 0,
      uid: nil,
      gid: nil,
      size: 0,
      mtime: 0,
      typeflag: TYPE_REGULAR,
      linkname: "",
      uname: nil,
      gname: nil
    )
      @values = {
        name:,
        mode:,
        uid:,
        gid:,
        size:,
        mtime: mtime.to_i,
        checksum: nil,
        typeflag:,
        linkname:,
        # GNU tar format uses "ustar " (space-padded), while POSIX ustar uses "ustar\0" (null-terminated).
        # The trailing space identifies this as GNU format, enabling GNU-specific extensions like long filenames.
        magic: "ustar ",
        version: " ",
        uname:,
        gname:,
        devmajor: nil,
        devminor: nil,
        prefix: "",
      }
    end

    def value_of(key)
      @values[key]
    end

    def to_binary
      fields = HeaderFields.new(self)
      fields.to_binary
    end

    def has_long_name?
      value_of(:name).bytesize > FIELDS[:name][:length]
    end
  end
end
