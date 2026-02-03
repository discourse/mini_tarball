# frozen_string_literal: true

module MiniTarball
  # Validates content source parameters for file and placeholder operations.
  # @api private
  module SourceValidator
    # Validates that exactly one content source is provided.
    #
    # @param from [String, nil] path to source file
    # @param content [String, nil] string content
    # @param block [Proc, nil] streaming block
    # @raise [ArgumentError] if not exactly one source is provided or from/content are not Strings
    def self.validate!(from, content, block)
      validate_type!(from, "from") unless from.nil?
      validate_type!(content, "content") unless content.nil?

      sources = [from, content, block].count { !_1.nil? }
      return if sources == 1

      raise ArgumentError, "Provide exactly one of: from:, content:, or a block"
    end

    private_class_method def self.validate_type!(value, label)
      return if value.is_a?(String)

      raise ArgumentError, "#{label}: must be a String"
    end
  end
end
