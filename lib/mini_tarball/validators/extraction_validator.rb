# frozen_string_literal: true

module MiniTarball
  # Validates extraction paths for security.
  # Prevents path traversal attacks during extraction.
  #
  # @api private
  module ExtractionValidator
    # Validates that extracting to a path is safe.
    #
    # @param name [String] the entry name from the archive
    # @param destination [String] the destination directory
    # @return [String] the validated full extraction path
    # @raise [PathTraversalError] if the path would escape destination
    def self.validate_extraction_path!(name, destination, allow_final_symlink: false)
      # Expand the destination to an absolute path
      dest_real = File.realpath(destination)

      # Build the target path (don't resolve symlinks yet)
      target_path = File.expand_path(name, dest_real)

      # The target must start with the destination directory
      unless target_path.start_with?(dest_real + File::SEPARATOR) || target_path == dest_real
        raise PathTraversalError,
              "Extraction path escapes destination: #{name} -> #{target_path} (dest: #{dest_real})"
      end

      ensure_no_symlink_components!(dest_real, target_path, allow_final_symlink:)

      target_path
    end

    # Validates a symlink target for extraction safety.
    #
    # The target is resolved one component at a time, following symlinks that
    # already exist on disk (created by earlier entries). A purely lexical
    # check is not enough: with an extracted symlink +l -> .+, the target
    # +l/../x+ resolves lexically to +x+ but physically to +../x+.
    #
    # @param link_path [String] the symlink's location (already validated)
    # @param target [String] the symlink target from the archive
    # @param destination [String] the destination directory
    # @return [String] the target (unchanged)
    # @raise [PathTraversalError] if following the symlink would escape destination,
    #   or if it passes through a symlink that cannot be resolved (dangling or looping)
    def self.validate_symlink_target!(link_path:, target:, destination:)
      dest_real = File.realpath(destination)

      if NameValidation.absolute_path?(target)
        # Absolute symlink targets are always rejected
        raise PathTraversalError, "Absolute symlink target not allowed: #{target}"
      end

      current = File.expand_path(File.dirname(link_path))
      ensure_within_destination!(current, dest_real, target:, link_path:)

      target
        .split("/")
        .each do |component|
          next if component.empty? || component == "."

          current =
            if component == ".."
              File.dirname(current)
            else
              resolve_physical_path(File.join(current, component))
            end
          ensure_within_destination!(current, dest_real, target:, link_path:)
        end

      target
    end

    # Validates that a path doesn't contain components that could cause issues.
    #
    # @param name [String] the entry name
    # @raise [PathTraversalError] if the name contains dangerous components
    def self.validate_name_components!(name)
      NameValidation.validate!(name, label: "name", error_class: PathTraversalError)
    end

    def self.ensure_no_symlink_components!(dest_real, target_path, allow_final_symlink:)
      relative = target_path.delete_prefix(dest_real)
      parts = relative.split(File::SEPARATOR).reject(&:empty?)

      return if parts.empty?

      parts_to_check = allow_final_symlink ? parts[0...-1] : parts
      current = dest_real

      parts_to_check.each do |part|
        current = File.join(current, part)
        if File.symlink?(current)
          raise PathTraversalError, "Symlink component not allowed: #{current}"
        end
      end
    end
    private_class_method :ensure_no_symlink_components!

    def self.ensure_within_destination!(path, dest_real, target:, link_path:)
      return if path == dest_real || path.start_with?(dest_real + File::SEPARATOR)

      raise PathTraversalError,
            "Symlink target escapes destination: #{target} from #{link_path} -> #{path}"
    end
    private_class_method :ensure_within_destination!

    # Resolves a path physically if it is an existing symlink.
    # Dangling or looping symlinks cannot be verified, so they are rejected.
    def self.resolve_physical_path(path)
      return path unless File.symlink?(path)

      File.realpath(path)
    rescue Errno::ENOENT, Errno::ELOOP
      raise PathTraversalError, "Symlink target cannot be resolved safely: #{path}"
    end
    private_class_method :resolve_physical_path
  end
end
