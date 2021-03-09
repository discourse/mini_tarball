# frozen_string_literal: true

module MiniTarball
  class Header
    # Size of each block in the tar file in bytes
    BLOCK_SIZE = 512 # bytes

    TYPE_REGULAR = "0"
    TYPE_LONG_LINK = "L"

    # rubocop:disable Layout/HashAlignment
    FIELDS = {
      name:     { length: 100, type: :chars },
      mode:     { length:   8, type: :mode },
      uid:      { length:   8, type: :number },
      gid:      { length:   8, type: :number },
      size:     { length:  12, type: :number },
      mtime:    { length:  12, type: :number },
      checksum: { length:   8, type: :checksum },
      typeflag: { length:   1, type: :chars },
      linkname: { length: 100, type: :chars },
      magic:    { length:   6, type: :chars },
      version:  { length:   2, type: :chars },
      uname:    { length:  32, type: :chars },
      gname:    { length:  32, type: :chars },
      devmajor: { length:   8, type: :number },
      devminor: { length:   8, type: :number },
      prefix:   { length: 155, type: :chars }
    }
    # rubocop:enable Layout/HashAlignment

    def initialize(name:, mode: 0, uid: nil, gid: nil, size: 0, mtime: 0, typeflag: TYPE_REGULAR, linkname: "", uname: nil, gname: nil)
      @values = {
        name: name,
        mode: mode,
        uid: uid,
        gid: gid,
        size: size,
        mtime: mtime.to_i,
        checksum: nil,
        typeflag: typeflag,
        linkname: linkname,
        magic: "ustar ",
        version: " ",
        uname: uname,
        gname: gname,
        devmajor: nil,
        devminor: nil,
        prefix: ""
      }
    end

    def value_of(key)
      @values[key]
    end
  end
end
