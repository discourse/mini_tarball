# frozen_string_literal: true

module MiniTarball
  # Formats values for tar header fields.
  # Handles octal encoding for small values and base-256 for large values.
  #
  # @api private
  module HeaderFormatter
    PERMISSION_BITMASK = 0007777

    # Pre-computed max octal values for common field lengths to avoid repeated allocation.
    # Key is field length, value is max value that fits in (length - 1) octal digits.
    MAX_OCTAL_VALUES = {
      8 => 0o7777777, # 7 octal digits: mode, uid, gid, checksum, devmajor, devminor
      12 => 0o77777777777, # 11 octal digits: size, mtime, atime, ctime
    }.freeze
    private_constant :MAX_OCTAL_VALUES

    # Formats a number for a tar header field.
    # Uses octal encoding if the value fits, otherwise base-256.
    #
    # @param value [Integer, nil] the value to format
    # @param length [Integer] the field length in bytes
    # @return [String, nil] formatted value, or nil if value is nil
    # @raise [ArgumentError] if value is negative
    # @raise [ValueTooLargeError] if value exceeds field capacity
    def self.format_number(value, length)
      return nil if !value
      raise ArgumentError, "Negative numbers are not supported: #{value}" if value < 0

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

    # Formats the header checksum field.
    #
    # @param checksum [Integer, nil] the checksum value
    # @return [String] formatted checksum with trailing null and space
    def self.format_checksum(checksum)
      length = Header::FIELDS[:checksum][:length]

      checksum ? format_number(checksum, length - 1) << "\0 " : " " * length
    end

    # Pads binary data to a multiple of the block size.
    #
    # @param binary [String] the data to pad
    # @return [String] padded data
    def self.zero_pad(binary)
      padding_length = (Header::BLOCK_SIZE - binary.length) % Header::BLOCK_SIZE
      padding_length > 0 ? binary + ("\0" * padding_length) : binary
    end

    private_class_method def self.fits_into_octal?(value, length)
      max_value = MAX_OCTAL_VALUES[length] || compute_max_octal(length)
      value <= max_value
    end

    private_class_method def self.compute_max_octal(length)
      (8**(length - 1)) - 1
    end

    private_class_method def self.to_octal(value, length)
      octal_length = length - 1
      "%0#{octal_length}o" % value
    end

    private_class_method def self.to_base256(value, length)
      encoded = Array.new(length, 0)
      encoded[0] = 0x80
      index = length - 1

      while value > 0 && index > 0
        encoded[index] = value % 256
        value /= 256
        index -= 1
      end

      raise ValueTooLargeError.new("Value is too large: #{value}") if value > 0

      encoded.pack("C#{length}")
    end
  end
end
