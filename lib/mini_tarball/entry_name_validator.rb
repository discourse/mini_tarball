# frozen_string_literal: true

module MiniTarball
  # Validates a tar entry name for safety (absolute paths, traversal, NUL bytes).
  #
  # @param name [String] the entry name
  # @return [void]
  # @raise [PathTraversalError] if the name contains dangerous components
  def self.validate_name!(name)
    ExtractionValidator.validate_name_components!(name)

    normalized = name.tr("\\", "/")
    if normalized == ".." || normalized.start_with?("../") || normalized.end_with?("/..") ||
         normalized.include?("/../")
      raise PathTraversalError, "Path traversal detected: #{name}"
    end
  end
end
