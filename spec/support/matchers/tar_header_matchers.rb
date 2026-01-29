# frozen_string_literal: true

RSpec::Matchers.define :have_tar_header_field do |field_name, expected_value|
  match do |tar_data|
    @actual_value = extract_field(tar_data, field_name)
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

  def extract_field(tar_data, field_name)
    header_data = tar_data[0, MiniTarball::Header::BLOCK_SIZE]
    offset = 0

    MiniTarball::Header::FIELDS.each do |name, field|
      if name == field_name
        raw = header_data[offset, field[:length]]
        return raw.delete("\0").strip
      end
      offset += field[:length]
    end

    raise ArgumentError, "Unknown tar header field: #{field_name}"
  end
end
