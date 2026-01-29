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

    # Writes a header to the stream.
    # Automatically prepends GNU extension headers for long names/links.
    #
    # @param header [Header] the header to write
    # @return [Integer] bytes written
    def write(header)
      write_long_name_header(header) if header.has_long_name?
      write_long_linkname_header(header) if header.has_long_linkname?
      @io.write(header.to_binary)
    end

    private def write_long_name_header(header)
      write_long_header(header, :name) { |value| Header.long_link_header(value) }
    end

    private def write_long_linkname_header(header)
      write_long_header(header, :linkname) { |value| Header.long_linkname_header(value) }
    end

    private def write_long_header(header, field)
      value = header.value_of(field)
      private_header = yield(value)
      binary_data = [value].pack("Z*")

      @io.write(private_header.to_binary)
      @io.write(HeaderFormatter.zero_pad(binary_data))
    end
  end
end
