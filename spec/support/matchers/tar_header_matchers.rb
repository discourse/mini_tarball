# frozen_string_literal: true

# Custom RSpec matcher for verifying tar header fields.
# Usage: expect(tar_data).to have_tar_header_field(:name, "file.txt")
RSpec::Matchers.define :have_tar_header_field do |field_name, expected_value|
  match do |tar_data|
    @actual_value = extract_field(tar_data, field_name, expected_value)
    @actual_value == expected_value
  end

  failure_message do
    "expected tar header field :#{field_name} to be #{expected_value.inspect}, " \
      "but was #{@actual_value.inspect}"
  end

  failure_message_when_negated do
    "expected tar header field :#{field_name} not to be #{expected_value.inspect}"
  end

  description { "have tar header field :#{field_name} equal to #{expected_value.inspect}" }

  # Locates and extracts a field from the tar header by walking through
  # FIELDS definitions to calculate the correct byte offset.
  def extract_field(tar_data, field_name, expected_value)
    header_data = tar_data[0, MiniTarball::Header::BLOCK_SIZE]
    offset = 0

    MiniTarball::Header::FIELDS.each do |name, field|
      if name == field_name
        raw = header_data[offset, field[:length]]
        return parse_field(raw, field, expected_value)
      end
      offset += field[:length]
    end

    raise ArgumentError, "Unknown tar header field: #{field_name}"
  end

  # Converts raw bytes to a comparable value based on field type.
  # When expected_value is a String, returns the raw octal representation
  # to allow testing the encoded format directly.
  def parse_field(raw, field, expected_value)
    case field[:type]
    when :number, :mode, :checksum
      # Allow string comparison for verifying raw octal encoding
      return raw.delete("\0").strip if expected_value.is_a?(String)
      decode_number(raw)
    else
      # String fields: strip trailing NULs and spaces
      raw.sub(/[\0 ]+\z/, "")
    end
  end

  # Decodes a numeric field, supporting both standard octal encoding
  # and GNU base-256 encoding (indicated by high bit set in first byte).
  def decode_number(raw)
    bytes = raw.bytes
    # Standard octal: ASCII digits terminated by NUL or space
    return raw.delete("\0").strip.to_i(8) unless (bytes[0] & 0x80) == 0x80

    # GNU base-256: high bit signals binary encoding, remaining bytes
    # are a big-endian integer (allows values > 8GB)
    value = 0
    bytes[1..].each { |byte| value = (value << 8) | byte }
    value
  end
end
