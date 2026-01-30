# frozen_string_literal: true

module MiniTarball
  # Encodes header field values into binary format.
  #
  # @api private
  class HeaderFields
    PACK_FORMAT = Header::FIELDS.values.map { |field| "a#{field[:length]}" }.join("").freeze
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
      Header::FIELDS.each_key do |name|
        value = @header.value_of(name)
        set_value(name, value)
      end

      update_checksum
      HeaderFormatter.zero_pad(encode_fields)
    end

    # Sets a field value, formatting it according to field type.
    #
    # @param name [Symbol] field name
    # @param value [Object] raw value
    # @return [void]
    private def set_value(name, value)
      field = Header::FIELDS[name]

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

    # Calculates and sets the header checksum.
    #
    # @return [void]
    private def update_checksum
      checksum = encode_fields.unpack("C*").sum
      set_value(:checksum, checksum)
    end

    private def encode_fields
      values = @values_by_field.values
      values.pack(PACK_FORMAT)
    end
  end
end
