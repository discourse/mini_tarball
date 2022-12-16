# frozen_string_literal: true

module MiniTarball
  ValueTooLargeError = Class.new(StandardError)

  module HeaderFormatter
    PERMISSION_BITMASK = 0007777

    # @param value [Integer]
    # @param length [Integer]
    def self.format_number(value, length)
      return nil if !value
      raise NotImplementedError.new("Negative numbers are not supported") if value.negative?

      if fits_into_octal?(value, length)
        to_octal(value, length)
      else
        to_base256(value, length)
      end
    end

    # Removes file type bitfields and returns file permissions as formatted number
    # @param value [Integer]
    # @param length [Integer]
    def self.format_permissions(value, length)
      format_number(value & PERMISSION_BITMASK, length)
    end

    def self.format_checksum(checksum)
      length = Header::FIELDS[:checksum][:length]

      if checksum
        format_number(checksum, length - 1) << "\0 "
      else
        " " * length
      end
    end

    def self.zero_pad(binary)
      padding_length = (Header::BLOCK_SIZE - binary.length) % Header::BLOCK_SIZE
      binary << "\0" * padding_length
    end

    private_class_method def self.fits_into_octal?(value, length)
      octal_length = length - 1
      max_octal_value = ("0" + "7" * octal_length).to_i(8)
      value <= max_octal_value
    end

    private_class_method def self.to_octal(value, length)
      octal_length = length - 1
      "%0#{octal_length}o" % value
    end

    # :reek:TooManyStatements { max_statements: 8}
    # :reek:UncommunicativeMethodName
    private_class_method def self.to_base256(value, length)
      encoded = Array.new(length, 0)
      encoded[0] = 0x80
      index = length - 1

      while value > 0
        raise ValueTooLargeError.new("Value is too large: #{value}") if index == 0
        encoded[index] = value % 256
        value /= 256
        index -= 1
      end

      encoded.pack("C#{length}")
    end
  end
end
