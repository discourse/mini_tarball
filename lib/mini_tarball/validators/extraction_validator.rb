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
    # @param link_path [String] the symlink's location (already validated)
    # @param target [String] the symlink target from the archive
    # @param destination [String] the destination directory
    # @return [String] the target (unchanged)
    # @raise [PathTraversalError] if following the symlink would escape destination
    def self.validate_symlink_target!(link_path, target, destination)
      dest_real = File.realpath(destination)

      # Resolve where the symlink would point to
      if target.start_with?("/")
        # Absolute symlink targets are always rejected
        raise PathTraversalError, "Absolute symlink target not allowed: #{target}"
      end

      # Calculate where the symlink points relative to its location
      link_dir = File.dirname(link_path)
      resolved_target = File.expand_path(target, link_dir)

      unless resolved_target.start_with?(dest_real + File::SEPARATOR) ||
               resolved_target == dest_real
        raise PathTraversalError,
              "Symlink target escapes destination: #{target} from #{link_path} -> #{resolved_target}"
      end

      target
    end

    # Validates that a path doesn't contain components that could cause issues.
    #
    # @param name [String] the entry name
    # @raise [PathTraversalError] if the name contains dangerous components
    def self.validate_name_components!(name)
      # Reject absolute paths
      if name.start_with?("/") || name.match?(/\A[A-Za-z]:/)
        raise PathTraversalError, "Absolute path not allowed: #{name}"
      end

      # Reject paths with null bytes
      if name.include?("\0")
        raise PathTraversalError, "Null bytes not allowed in path: #{name.inspect}"
      end

      # Reject Windows-style paths on Unix
      if name.include?("\\")
        # Convert to forward slashes for checking
        normalized = name.tr("\\", "/")
        if normalized.start_with?("/") || normalized.include?("/../") ||
             normalized.start_with?("../")
          raise PathTraversalError, "Path traversal detected: #{name}"
        end
      end
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
  end
end
