# frozen_string_literal: true

module MiniTarball
  # Validates archive entry names and link targets for security.
  # Rejects absolute paths and path traversal attempts.
  #
  # @api private
  module PathValidator
    # Validates an entry name for archive inclusion.
    #
    # @param name [String] the entry name
    # @return [void]
    # @raise [UnsafeNameError] if name is empty, absolute, contains traversal, or has NUL bytes
    def self.validate_name!(name)
      NameValidation.validate!(name, label: "name", error_class: UnsafeNameError)
    end

    # Validates a symlink/hardlink target.
    #
    # @param target [String] the link target
    # @param allow_parent_references [Boolean] whether to allow parent directory references (..)
    # @return [void]
    # @raise [UnsafeNameError] if target is empty, absolute, has NUL bytes, or contains
    #   path traversal (unless allow_parent_references is true)
    def self.validate_target!(target, allow_parent_references: false)
      NameValidation.validate!(
        target,
        label: "target",
        error_class: UnsafeNameError,
        allow_parent_references: allow_parent_references,
      )
    end
  end
end
