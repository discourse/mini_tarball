# frozen_string_literal: true

module MiniTarball
  class InvalidHeaderError < StandardError
    def initialize(msg = "Invalid tar header")
      super
    end
  end

  class ChecksumMismatchError < InvalidHeaderError
    def initialize(msg = "Header checksum mismatch")
      super
    end
  end

  class HeaderParser
    def self.parse(binary_data)
      return nil if binary_data.nil?
      raise InvalidHeaderError, "Truncated header" if binary_data.bytesize < Header::BLOCK_SIZE
      return nil if end_of_archive?(binary_data)

      values = unpack_fields(binary_data)
      validate_checksum!(binary_data, values[:checksum])

      values
    end

    def self.end_of_archive?(data)
      data == "\0" * Header::BLOCK_SIZE
    end

    class << self
      private

      def unpack_fields(data)
        values = {}
        offset = 0

        Header::FIELDS.each do |name, field|
          raw = data[offset, field[:length]]
          values[name] = parse_field(raw, field[:type])
          offset += field[:length]
        end

        values
      end

      def parse_field(raw, type)
        case type
        when :number, :mode, :checksum
          parse_number(raw)
        when :chars
          raw.delete("\0").strip
        end
      end

      def parse_number(raw)
        return nil if raw.nil?

        # Check for base-256 encoding (high bit set)
        if raw.getbyte(0) & 0x80 != 0
          parse_base256(raw)
        else
          stripped = raw.strip
          return nil if stripped.empty?

          # Reject negative octal values
          if stripped.start_with?("-")
            raise InvalidHeaderError, "Negative octal values not supported"
          end

          stripped.to_i(8)
        end
      end

      def parse_base256(raw)
        # Check sign bit (bit 6 of first byte after marker)
        if raw.getbyte(0) & 0x40 != 0
          raise InvalidHeaderError, "Negative base-256 values not supported"
        end

        bytes = raw.bytes
        bytes[0] &= 0x7F # Clear the marker bit
        bytes.inject(0) { |acc, byte| (acc << 8) | byte }
      end

      def validate_checksum!(data, stored_checksum)
        # Replace checksum field with spaces for calculation
        checksum_offset =
          Header::FIELDS
            .keys
            .take_while { |k| k != :checksum }
            .sum { |k| Header::FIELDS[k][:length] }
        checksum_length = Header::FIELDS[:checksum][:length]

        data_for_checksum = data.dup
        data_for_checksum[checksum_offset, checksum_length] = " " * checksum_length

        calculated = data_for_checksum.bytes.sum

        raise ChecksumMismatchError if calculated != stored_checksum
      end
    end
  end
end
