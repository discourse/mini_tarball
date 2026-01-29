# frozen_string_literal: true

module MiniTarball
  # Represents a tar archive entry header.
  #
  # @api private
  class Header
    # Size of each block in the tar file in bytes.
    BLOCK_SIZE = 512

    # @!group Entry Type Constants
    TYPE_REGULAR = "0"
    TYPE_HARDLINK = "1"
    TYPE_SYMLINK = "2"
    TYPE_DIRECTORY = "5"
    # @!endgroup

    TYPE_LONG_LINK = "L"
    TYPE_LONG_LINKNAME = "K"
    private_constant :TYPE_LONG_LINK, :TYPE_LONG_LINKNAME

    # Field definitions for the tar header format.

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

    # Creates a GNU extension header for long filenames.
    #
    # @param name [String] the filename exceeding 100 bytes
    # @return [Header] a header with typeflag 'L'
    def self.long_link_header(name)
      gnu_extension_header(name, TYPE_LONG_LINK)
    end

    # Creates a GNU extension header for long link targets.
    #
    # @param target [String] the link target exceeding 100 bytes
    # @return [Header] a header with typeflag 'K'
    def self.long_linkname_header(target)
      gnu_extension_header(target, TYPE_LONG_LINKNAME)
    end

    private_class_method def self.gnu_extension_header(content, typeflag)
      Header.new(
        name: "././@LongLink",
        mode: 0644,
        uid: 0,
        gid: 0,
        size: content.bytesize + 1,
        typeflag:,
        uname: "root",
        gname: "root",
      )
    end

    # Creates a new header with the given field values.
    #
    # @param name [String] entry name
    # @param mode [Integer] file permissions
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param size [Integer] file size in bytes
    # @param mtime [Time, Integer] modification time
    # @param typeflag [String] entry type (see TYPE_* constants)
    # @param linkname [String] link target for symlinks/hardlinks
    # @param uname [String, nil] owner username
    # @param gname [String, nil] group name
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

    # Returns the value of a header field.
    #
    # @param key [Symbol] field name (e.g., :name, :size, :mode)
    # @return [Object] the field value
    def value_of(key)
      @values[key]
    end

    # Serializes the header to a 512-byte binary block.
    #
    # @return [String] binary header data
    def to_binary
      fields = HeaderFields.new(self)
      fields.to_binary
    end

    # Returns whether the filename exceeds 100 bytes.
    #
    # @return [Boolean]
    def has_long_name?
      value_of(:name).bytesize > FIELDS[:name][:length]
    end

    # Returns whether the link target exceeds 100 bytes.
    #
    # @return [Boolean]
    def has_long_linkname?
      value_of(:linkname).bytesize > FIELDS[:linkname][:length]
    end
  end
end
