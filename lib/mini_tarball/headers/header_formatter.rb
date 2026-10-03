# frozen_string_literal: true

module MiniTarball
  # Formats values for tar header fields.
  # Handles octal encoding for small values and base-256 for large values.
  #
  # @api private
  module HeaderFormatter
    PERMISSION_BITMASK = 0007777

    # Pre-computed max octal values for supported field lengths.
    # Key is field length, value is max value that fits in (length - 1) octal digits.
    MAX_OCTAL_VALUES = {
      7 => 0o777777, # 6 octal digits: checksum uses length - 1
      8 => 0o7777777, # 7 octal digits: mode, uid, gid, checksum, devmajor, devminor
      12 => 0o77777777777, # 11 octal digits: size, mtime, atime, ctime
    }.freeze
    OCTAL_FORMATS =
      MAX_OCTAL_VALUES.keys.to_h { |length| [length, "%0#{length - 1}o".freeze] }.freeze
    CHECKSUM_LENGTH = Header::FIELDS.fetch(:checksum).fetch(:length)
    EMPTY_CHECKSUM = (" " * CHECKSUM_LENGTH).freeze
    private_constant :MAX_OCTAL_VALUES, :OCTAL_FORMATS, :CHECKSUM_LENGTH, :EMPTY_CHECKSUM

    # Formats a number for a tar header field.
    # Uses octal encoding if the value fits, otherwise base-256.
    # Negative values always use base-256.
    #
    # @param value [Integer, nil] the value to format
    # @param length [Integer] the field length in bytes
    # @return [String, nil] formatted value, or nil if value is nil
    # @raise [ArgumentError] if the field length isn't supported
    # @raise [ValueTooLargeError] if value exceeds field capacity
    def self.format_number(value, length)
      return nil if !value

      fits_into_octal?(value, length) ? to_octal(value, length) : to_base256(value, length)
    end

    # Formats file permissions, stripping file type bits.
    #
    # @param value [Integer] mode value including file type bits
    # @param length [Integer] the field length in bytes
    # @return [String] formatted permissions
    def self.format_permissions(value, length)
      format_number(value & PERMISSION_BITMASK, length)
    end

    # @param checksum [Integer, nil] the checksum value
    # @return [String] formatted checksum with trailing null and space, or only
    #   spaces if checksum is nil
    def self.format_checksum(checksum)
      checksum ? format_number(checksum, CHECKSUM_LENGTH - 1) << "\0 " : EMPTY_CHECKSUM
    end

    # Pads binary data to a multiple of the block size.
    #
    # @param binary [String] the data to pad
    # @return [String] padded data
    def self.zero_pad(binary)
      binary + ("\0" * ((Header::BLOCK_SIZE - binary.length) % Header::BLOCK_SIZE))
    end

    private_class_method def self.fits_into_octal?(value, length)
      max_value =
        MAX_OCTAL_VALUES.fetch(length) do
          raise ArgumentError, "Unsupported octal field length: #{length}"
        end
      value.between?(0, max_value)
    end

    private_class_method def self.to_octal(value, length)
      OCTAL_FORMATS.fetch(length) % value
    end

    # The field is a big-endian two's complement number, like GNU tar writes it.
    # The first byte is 0x80 for positive values and 0xFF for negative values,
    # so the value has to fit into the other bytes.
    private_class_method def self.to_base256(value, length)
      limit = 256**(length - 1)
      unless value.between?(-limit, limit - 1)
        raise ValueTooLargeError, "Value is too large for a #{length}-byte header field: #{value}"
      end

      # pack("C") keeps only the lowest 8 bits of each number.
      bytes = Array.new(length) { |index| value >> ((length - 1 - index) * 8) }
      bytes[0] |= 0x80
      bytes.pack("C*")
    end
  end
end
