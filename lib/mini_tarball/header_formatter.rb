# frozen_string_literal: true

module MiniTarball
  ValueTooLargeError = Class.new(StandardError)

  class HeaderFormatter
    # @param value [Integer]
    # @param length [Integer]
    def self.format_number(value, length)
      return nil if value.nil?
      raise NotImplementedError.new("Negative numbers are not supported") if value.negative?

      octal_length = length - 1
      max_octal_value = ("0" + "7" * octal_length).to_i(8)

      if (value <= max_octal_value)
        to_octal(value, octal_length)
      else
        to_base256(value, length)
      end
    end

    def self.to_octal(value, length)
      "%0#{length}o" % value
    end

    def self.to_base256(value, length)
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
