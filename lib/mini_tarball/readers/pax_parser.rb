# frozen_string_literal: true

module MiniTarball
  # Parses pax extended header data.
  #
  # Pax extended headers consist of records in the format:
  #   length key=value\n
  #
  # where length is the total record length including the length field itself.
  #
  # @api private
  module PaxParser
    # Parses pax extended header data into a hash of attributes.
    #
    # @param data [String] the raw pax header data
    # @return [Hash{String => String}] parsed key-value pairs
    # @raise [InvalidHeaderError] if the data is malformed
    def self.parse(data)
      attributes = {}
      offset = 0

      while offset < data.bytesize
        # Find the space after the length
        space_index = data.index(" ", offset)
        raise InvalidHeaderError, "Invalid pax header: missing space" unless space_index

        # Parse the length
        length_str = data.byteslice(offset, space_index - offset)
        length = Integer(length_str, 10)
        raise InvalidHeaderError, "Invalid pax record length: #{length_str}" if length <= 0

        # Extract the full record (length includes everything up to and including newline)
        record = data.byteslice(offset, length)
        raise InvalidHeaderError, "Truncated pax record" if record.bytesize < length

        # Parse key=value from the record (skip length, space at start and newline at end)
        kv_start = space_index - offset + 1
        kv_end = length - 1 # Exclude trailing newline
        kv_data = record.byteslice(kv_start, kv_end - kv_start)

        # Find the equals sign
        equals_index = kv_data.index("=")
        raise InvalidHeaderError, "Invalid pax record: missing equals sign" unless equals_index

        key = kv_data.byteslice(0, equals_index)
        value = kv_data.byteslice(equals_index + 1, kv_data.bytesize - equals_index - 1)

        # Ensure proper UTF-8 encoding
        key = key.force_encoding(Encoding::UTF_8)
        value = value.force_encoding(Encoding::UTF_8)

        attributes[key] = value
        offset += length
      end

      attributes
    rescue ArgumentError => e
      raise InvalidHeaderError, "Invalid pax header: #{e.message}"
    end
  end
end
