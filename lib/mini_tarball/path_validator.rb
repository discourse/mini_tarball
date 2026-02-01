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
      raise UnsafeNameError, "Empty name not allowed" if name.nil? || name.empty?
      raise UnsafeNameError, "NUL bytes not allowed in name" if name.include?("\0")
      raise UnsafeNameError, "Absolute paths are not allowed: #{name}" if absolute_path?(name)
      raise UnsafeNameError, "Path traversal is not allowed: #{name}" if path_traversal?(name)
    end

    # Validates a symlink/hardlink target.
    #
    # @param target [String] the link target
    # @param allow_parent_references [Boolean] whether to allow parent directory references (..)
    # @return [void]
    # @raise [UnsafeNameError] if target is empty, absolute, has NUL bytes, or contains
    #   path traversal (unless allow_traversal is true)
    def self.validate_target!(target, allow_parent_references: false)
      raise UnsafeNameError, "Empty target not allowed" if target.nil? || target.empty?
      raise UnsafeNameError, "NUL bytes not allowed in target" if target.include?("\0")
      if absolute_path?(target)
        raise UnsafeNameError, "Absolute target paths are not allowed: #{target}"
      end
      if !allow_parent_references && path_traversal?(target)
        raise UnsafeNameError, "Path traversal is not allowed in target: #{target}"
      end
    end

    # Checks if a path is absolute or drive-relative (Unix or Windows).
    private_class_method def self.absolute_path?(path)
      # Unix absolute || Windows drive letter (C:\foo or C:foo) || Windows UNC
      path.start_with?("/") || path.match?(/\A[A-Za-z]:/) || path.start_with?("\\")
    end

    # Checks if a path contains directory traversal sequences.
    private_class_method def self.path_traversal?(name)
      normalized = name.tr("\\", "/")
      normalized == ".." || normalized.start_with?("../") || normalized.end_with?("/..") ||
        normalized.include?("/../")
    end
  end
end
