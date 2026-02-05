# frozen_string_literal: true

module MiniTarball
  # Represents a tar archive entry header.
  #
  # @api private
  class Header
    # Size of each block in the tar file in bytes.
    BLOCK_SIZE = 512
    END_OF_ARCHIVE_BLOCKS = 2
    END_OF_ARCHIVE_SIZE = BLOCK_SIZE * END_OF_ARCHIVE_BLOCKS

    # Entry type flags.
    TYPE =
      {
        regular: "0",
        hardlink: "1",
        symlink: "2",
        directory: "5",
        pax_extended: "x",
        pax_global: "g",
        gnu_long_name: "L",
        gnu_long_linkname: "K",
      }.freeze

    # Attributes used for GNU extension headers (long filenames/linknames)
    GNU_EXTENSION_ATTRS =
      EntryAttributes.new(
        mode: 0644,
        uid: 0,
        gid: 0,
        uname: "root",
        gname: "root",
        mtime: Time.at(0).utc,
      ).freeze
    private_constant :GNU_EXTENSION_ATTRS

    # Creates a GNU extension header for long filenames.
    #
    # @param name [String] the filename exceeding 100 bytes
    # @return [Header] a header with typeflag 'L'
    def self.long_link_header(name)
      gnu_extension_header(name, TYPE[:gnu_long_name])
    end

    # Creates a GNU extension header for long link targets.
    #
    # @param target [String] the link target exceeding 100 bytes
    # @return [Header] a header with typeflag 'K'
    def self.long_linkname_header(target)
      gnu_extension_header(target, TYPE[:gnu_long_linkname])
    end

    private_class_method def self.gnu_extension_header(content, typeflag)
      Header.new(
        name: "././@LongLink",
        size: content.bytesize + 1,
        typeflag:,
        attrs: GNU_EXTENSION_ATTRS,
      )
    end

    # Creates a new header with the given field values.
    #
    # @param name [String] entry name
    # @param size [Integer] file size in bytes
    # @param typeflag [String] entry type (see TYPE map)
    # @param linkname [String] link target for symlinks/hardlinks
    # @param attrs [EntryAttributes, nil] entry attributes (mode, uid, gid, uname, gname, mtime)
    def initialize(name:, size: 0, typeflag: TYPE[:regular], linkname: "", attrs: nil)
      @values = {
        name:,
        mode: attrs&.mode || 0,
        uid: attrs&.uid,
        gid: attrs&.gid,
        size:,
        mtime: (attrs&.mtime || Time.now.utc).to_i,
        checksum: nil,
        typeflag:,
        linkname:,
        # GNU tar format uses "ustar " (space-padded), while POSIX ustar uses "ustar\0" (null-terminated).
        # The trailing space identifies this as GNU format, enabling GNU-specific extensions like long filenames.
        magic: "ustar ",
        version: " ",
        uname: attrs&.uname,
        gname: attrs&.gname,
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
      value_of(:name).bytesize > Headers::Layout::FIELD_MAP[:name][:length]
    end

    # Returns whether the link target exceeds 100 bytes.
    #
    # @return [Boolean]
    def has_long_linkname?
      value_of(:linkname).bytesize > Headers::Layout::FIELD_MAP[:linkname][:length]
    end

    # Returns the padding needed to align to the next block boundary.
    #
    # @param size [Integer] the size to align
    # @return [Integer] padding length
    def self.padding_for(size)
      (BLOCK_SIZE - (size % BLOCK_SIZE)) % BLOCK_SIZE
    end
  end
end
