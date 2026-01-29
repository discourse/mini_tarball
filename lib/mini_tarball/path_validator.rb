# frozen_string_literal: true

module MiniTarball
  # Validates archive entry names and link targets for security.
  # Rejects absolute paths and path traversal attempts.
  #
  # @api private
  module PathValidator
    module_function

    # Validates an entry name for archive inclusion.
    #
    # @param name [String] the entry name
    # @return [void]
    # @raise [UnsafeNameError] if name is empty, absolute, or contains traversal
    def validate_name!(name)
      raise UnsafeNameError, "Empty name not allowed" if name.nil? || name.empty?
      raise UnsafeNameError, "Absolute paths are not allowed: #{name}" if absolute_path?(name)
      raise UnsafeNameError, "Path traversal is not allowed: #{name}" if path_traversal?(name)
    end

    # Validates a symlink/hardlink target.
    #
    # @param target [String] the link target
    # @return [void]
    # @raise [UnsafeNameError] if target is empty or absolute
    def validate_target!(target)
      raise UnsafeNameError, "Empty target not allowed" if target.nil? || target.empty?
      if absolute_path?(target)
        raise UnsafeNameError, "Absolute target paths are not allowed: #{target}"
      end
    end

    # Checks if a path is absolute (Unix or Windows).
    #
    # @param path [String] the path to check
    # @return [Boolean]
    def absolute_path?(path)
      # Unix absolute || Windows drive letter || Windows UNC
      path.start_with?("/") || path.match?(%r{\A[A-Za-z]:[\\/]}) || path.start_with?("\\")
    end

    # Checks if a path contains directory traversal sequences.
    #
    # @param name [String] the path to check
    # @return [Boolean]
    def path_traversal?(name)
      normalized = name.tr("\\", "/")
      normalized == ".." || normalized.start_with?("../") || normalized.end_with?("/..") ||
        normalized.include?("/../")
    end
  end
end
