# frozen_string_literal: true

module MiniTarball
  class HeaderFields
    def self.pack_format
      @pack_format ||= Header::FIELDS.values.map { |field| "a#{field[:length]}" }.join("")
    end

    def initialize(header)
      @header = header
      @values_by_field = {}
    end

    def to_binary
      Header::FIELDS.each_key do |name|
        value = @header.value_of(name)
        set_value(name, value)
      end

      update_checksum
      HeaderFormatter.zero_pad(encode_fields)
    end

    # :reek:DuplicateMethodCall
    def set_value(name, value)
      field = Header::FIELDS[name]

      case field[:type]
      when :number
        @values_by_field[name] = HeaderFormatter.format_number(value, field[:length])
      when :mode
        @values_by_field[name] = HeaderFormatter.format_permissions(value, field[:length])
      when :checksum
        @values_by_field[name] = HeaderFormatter.format_checksum(value)
      else
        @values_by_field[name] = value
      end
    end

    def update_checksum
      checksum = encode_fields.unpack("C*").sum
      set_value(:checksum, checksum)
    end

    private def encode_fields
      values = @values_by_field.values
      values.pack(HeaderFields.pack_format)
    end
  end
end
