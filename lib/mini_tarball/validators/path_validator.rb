# frozen_string_literal: true

module MiniTarball
  # Validates archive entry names and link targets for security.
  # Rejects absolute paths and path traversal attempts.
  #
  # @api private
  module PathValidator
    # @param name [String] the entry name
    # @return [void]
    # @raise [UnsafeNameError] if name is empty, absolute, contains traversal, or has NUL bytes
    def self.validate_name!(name)
      validate_path!(name, label: "name")
    end

    # @param target [String] the link target
    # @param allow_parent_references [Boolean] whether to allow parent directory references (..)
    # @return [void]
    # @raise [UnsafeNameError] if target is empty, absolute, has NUL bytes, or contains
    #   path traversal (unless allow_parent_references is true)
    def self.validate_target!(target, allow_parent_references: false)
      validate_path!(target, label: "target", allow_parent_references:)
    end

    private_class_method def self.validate_path!(value, label:, allow_parent_references: false)
      raise UnsafeNameError, "Empty #{label} not allowed" if value.nil? || value == ""
      unless value.is_a?(String)
        raise ArgumentError, "#{label} must be a String, got #{value.class}"
      end
      raise UnsafeNameError, "NUL bytes not allowed in #{label}" if value.include?("\0")

      # Tar stores names as bytes. File names can contain bytes that are invalid
      # in UTF-8, and regular expressions and String#tr raise an error for them.
      path = value.valid_encoding? ? value : value.b
      if absolute_path?(path)
        raise UnsafeNameError, "Absolute paths are not allowed in #{label}: #{value}"
      end
      if !allow_parent_references && path_traversal?(path)
        raise UnsafeNameError, "Path traversal is not allowed in #{label}: #{value}"
      end
    end

    # Checks if a path is absolute or drive-relative (Unix or Windows).
    private_class_method def self.absolute_path?(path)
      # Unix absolute || Windows drive letter (C:\foo or C:foo) || Windows UNC
      path.start_with?("/") || path.match?(/\A[A-Za-z]:/) || path.start_with?("\\")
    end

    private_class_method def self.path_traversal?(name)
      normalized = name.tr("\\", "/")
      normalized == ".." || normalized.start_with?("../") || normalized.end_with?("/..") ||
        normalized.include?("/../")
    end
  end
end
