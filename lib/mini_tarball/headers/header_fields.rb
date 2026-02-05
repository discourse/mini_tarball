# frozen_string_literal: true

module MiniTarball
  # Encodes header field values into binary format.
  #
  # @api private
  class HeaderFields
    PACK_FORMAT = Headers::Layout::PACK_FORMAT
    private_constant :PACK_FORMAT

    # @param header [Header] the header to encode
    def initialize(header)
      @header = header
      @values_by_field = {}
    end

    # Encodes all fields and returns the binary header block.
    #
    # @return [String] 512-byte binary header
    def to_binary
      Headers::Layout::FIELDS.each do |name, _length, _type|
        set_value(name, @header.value_of(name))
      end

      update_checksum
      HeaderFormatter.zero_pad(encode_fields)
    end

    private def set_value(name, value)
      field = Headers::Layout::FIELD_MAP[name]

      @values_by_field[name] = case field[:type]
      in :number
        HeaderFormatter.format_number(value, field[:length])
      in :mode
        HeaderFormatter.format_permissions(value, field[:length])
      in :checksum
        HeaderFormatter.format_checksum(value)
      else
        value
      end
    end

    private def update_checksum
      checksum = encode_fields.unpack("C*").sum
      set_value(:checksum, checksum)
    end

    private def encode_fields
      values = Headers::Layout::FIELDS.map { |name, _length, _type| @values_by_field[name] }
      values.pack(PACK_FORMAT)
    end
  end
end
