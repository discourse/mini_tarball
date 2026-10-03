# frozen_string_literal: true

module MiniTarball
  # Validates content source parameters for file and placeholder operations.
  # @api private
  module SourceValidator
    # Validates that exactly one content source is provided.
    #
    # @param from [String, #to_path, nil] path to source file
    # @param content [String, nil] string content
    # @param block [Proc, nil] streaming block
    # @raise [ArgumentError] if not exactly one source is provided, +from:+ is not a path
    #   or +content:+ is not a String
    def self.validate!(from:, content:, block:)
      validate_path!(from) unless from.nil?
      validate_content!(content) unless content.nil?

      sources = [from, content, block].count { !_1.nil? }
      return if sources == 1

      raise ArgumentError, "Provide exactly one of: from:, content:, or a block"
    end

    # Accepts the same paths as File.open.
    private_class_method def self.validate_path!(from)
      return if from.respond_to?(:to_str) || from.respond_to?(:to_path)

      raise ArgumentError, "from: must be a String or respond to to_path"
    end

    private_class_method def self.validate_content!(content)
      return if content.is_a?(String)

      raise ArgumentError, "content: must be a String"
    end
  end
end
