# frozen_string_literal: true

module MiniTarball
  class HeaderWriter
    def initialize(io)
      @io = io
    end

    def write(header)
      write_long_name_header(header) if header.has_long_name?
      @io.write(header.to_binary)
    end

    private def write_long_name_header(header)
      name = header.value_of(:name)
      private_header = Header.long_link_header(name)
      binary_data = [name].pack("Z*")

      @io.write(private_header.to_binary)
      @io.write(HeaderFormatter.zero_pad(binary_data))
    end
  end
end
