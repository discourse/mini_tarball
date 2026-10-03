# frozen_string_literal: true

module MiniTarball
  # Writes tar headers to an IO stream.
  # Handles GNU long filename/linkname extensions automatically.
  #
  # @api private
  class HeaderWriter
    # @param io [IO] the output stream
    def initialize(io)
      @io = io
    end

    # Automatically prepends GNU extension headers for long names/links.
    #
    # @param header [Header] the header to write
    # @return [Integer] total bytes written (including any GNU extension headers)
    def write(header)
      blocks = encode(header)
      @io.write(blocks)
      blocks.bytesize
    end

    # Encodes a header and its GNU extension headers without writing anything.
    #
    # Nothing is written until all blocks are encoded. If the main header
    # failed after the long name block was written, the next entry in the
    # archive would get that long name.
    #
    # @param header [Header] the header to encode
    # @return [String] the binary header blocks
    # @raise [ValueTooLargeError, ArgumentError] if a header value can't be encoded
    def encode(header)
      long_linkname = header.has_long_linkname?
      long_name = header.has_long_name?
      main_block = header.to_binary
      # Most entries have no GNU extension blocks, so this saves a copy per entry
      return main_block unless long_linkname || long_name

      blocks = String.new
      # Emit long linkname before long name so the long name header directly precedes the entry.
      blocks << long_linkname_blocks(header) if long_linkname
      blocks << long_name_blocks(header) if long_name
      blocks << main_block
    end

    private def long_name_blocks(header)
      long_header_blocks(header, :name) { |value| Header.long_link_header(value) }
    end

    private def long_linkname_blocks(header)
      long_header_blocks(header, :linkname) { |value| Header.long_linkname_header(value) }
    end

    private def long_header_blocks(header, field)
      value = header.value_of(field)
      private_header = yield(value)
      binary_data = [value].pack("Z*")

      private_header.to_binary + HeaderFormatter.zero_pad(binary_data)
    end
  end
end
