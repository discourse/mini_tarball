# frozen_string_literal: true

# Custom RSpec matcher for verifying NUL byte padding in binary data.
# Usage: expect(data).to have_null_padding(at: 515, bytes: 509)
RSpec::Matchers.define :have_null_padding do |at:, bytes:|
  match do |data|
    @actual = data[at, bytes]
    @expected = "\0" * bytes
    @actual == @expected
  end

  failure_message do
    non_null_positions = []
    @actual.each_byte.with_index { |byte, i| non_null_positions << (at + i) if byte != 0 }

    "expected #{bytes} NUL bytes at offset #{at}, " \
      "but found non-NUL bytes at positions: #{non_null_positions.first(10).join(", ")}" \
      "#{non_null_positions.size > 10 ? " (and #{non_null_positions.size - 10} more)" : ""}"
  end

  description { "have #{bytes} NUL bytes at offset #{at}" }
end
