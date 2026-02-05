# frozen_string_literal: true

module MiniTarball
  # Shared validation helpers for archive entry names and targets.
  #
  # @api private
  module NameValidation
    def self.validate!(name, label:, error_class:, allow_parent_references: false)
      raise error_class, "Empty #{label} not allowed" if name.nil? || name.empty?
      raise error_class, "NUL bytes not allowed in #{label}" if name.include?("\0")

      if absolute_path?(name)
        raise error_class, "Absolute paths are not allowed in #{label}: #{name}"
      end

      if !allow_parent_references && path_traversal?(name)
        raise error_class, "Path traversal is not allowed in #{label}: #{name}"
      end
    end

    def self.absolute_path?(path)
      # Unix absolute || Windows drive letter (C:\foo or C:foo) || Windows UNC
      path.start_with?("/") || path.match?(/\A[A-Za-z]:/) || path.start_with?("\\")
    end

    def self.path_traversal?(name)
      normalized = name.tr("\\", "/")
      normalized == ".." || normalized.start_with?("../") || normalized.end_with?("/..") ||
        normalized.include?("/../")
    end
  end
  private_constant :NameValidation
end
