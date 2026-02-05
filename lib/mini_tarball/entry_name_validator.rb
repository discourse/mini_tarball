# frozen_string_literal: true

module MiniTarball
  # Validates a tar entry name for safety (absolute paths, traversal, NUL bytes).
  #
  # @param name [String] the entry name
  # @return [void]
  # @raise [PathTraversalError] if the name contains dangerous components
  def self.validate_name!(name)
    NameValidation.validate!(name, label: "name", error_class: PathTraversalError)
  end
end
