# frozen_string_literal: true

module MiniTarball
  class HeaderWriter
    def initialize(io)
      @io = io
    end

    def write(header)
      write_long_name_header(header) if has_long_name?(header)
      @io.write(to_binary(header))
    end

    private

    def to_binary(header)
      values_by_field = {}

      Header::FIELDS.each do |name, field|
        value = values_by_field[name] = header.value_of(name)

        case field[:type]
        when :number
          values_by_field[name] = HeaderFormatter.format_number(value, field[:length])
        when :mode
          values_by_field[name] = HeaderFormatter.format_permissions(value, field[:length])
        when :checksum
          values_by_field[name] = " " * field[:length]
        end
      end

      update_checksum(values_by_field)
      add_padding(encode(values_by_field.values))
    end

    def update_checksum(values_by_field)
      checksum = encode(values_by_field.values).unpack("C*").sum
      values_by_field[:checksum] = format_checksum(checksum)
    end

    def format_checksum(checksum)
      length = Header::FIELDS[:checksum][:length] - 1
      HeaderFormatter.format_number(checksum, length) << "\0 "
    end

    def encode(values)
      @pack_format ||= Header::FIELDS.values
        .map { |field| "a#{field[:length]}" }
        .join("")

      values.pack(@pack_format)
    end

    def add_padding(binary)
      padding_length = (Header::BLOCK_SIZE - binary.length) % Header::BLOCK_SIZE
      binary << "\0" * padding_length
    end

    def has_long_name?(header)
      header.value_of(:name).bytesize > Header::FIELDS[:name][:length]
    end

    def write_long_name_header(header)
      name = header.value_of(:name)
      private_header = long_link_header(name, Header::TYPE_LONG_LINK)
      data = [header.value_of(:name)].pack("Z*")

      @io.write(to_binary(private_header))
      @io.write(add_padding(data))
    end

    def long_link_header(name, type)
      Header.new(
        name: "././@LongLink",
        mode: 0644,
        uid: 0,
        gid: 0,
        size: name.bytesize + 1,
        typeflag: type,
        uname: "root",
        gname: "root"
      )
    end
  end
end
