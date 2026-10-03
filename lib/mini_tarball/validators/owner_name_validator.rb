# frozen_string_literal: true

module MiniTarball
  # Checks user and group names for the 32-byte uname and gname header fields.
  # Longer names would be cut off, and control characters like newlines would
  # show up in archive listings.
  #
  # @api private
  module OwnerNameValidator
    CONTROL_CHARACTERS = /[[:cntrl:]]/
    private_constant :CONTROL_CHARACTERS

    # @param value [Object] the name to check
    # @return [Boolean] whether the name can be stored as is
    def self.valid?(value)
      value.is_a?(String) && value.bytesize <= max_bytesize && !control_characters?(value)
    end

    # @param value [String, nil] the name to check; nil means "not set"
    # @param label [String] field name for error messages
    # @return [void]
    # @raise [ArgumentError] if the name can't be stored as is
    def self.validate!(value, label:)
      return if value.nil? || valid?(value)

      raise ArgumentError,
            "#{label} must be a String of at most #{max_bytesize} bytes " \
              "without control characters: #{value.inspect}"
    end

    # The header stores the name as bytes, so bytes that are invalid in the
    # encoding of the String are fine. Regular expressions raise an error for
    # them, so the check uses a binary copy.
    private_class_method def self.control_characters?(value)
      (value.valid_encoding? ? value : value.b).match?(CONTROL_CHARACTERS)
    end

    # uname and gname have the same size.
    private_class_method def self.max_bytesize
      Header::FIELDS.fetch(:uname).fetch(:length)
    end
  end
end
