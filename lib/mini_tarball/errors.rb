# frozen_string_literal: true

module MiniTarball
  # Base class for all MiniTarball errors.
  class Error < StandardError
  end

  # Raised when the provided IO object doesn't support required operations (pos, write, close).
  class NoIOLikeObjectError < Error
    def initialize(msg = "IO object is not valid")
      super
    end
  end

  # Raised when a seekable IO is required but the provided IO doesn't support seeking.
  # This occurs when using {Writer#add_file_from_stream} without a size parameter
  # or when using {Writer#fill}.
  class NotSeekableError < Error
    def initialize(msg = "IO object is not seekable")
      super
    end
  end

  # Raised when a filename or path contains unsafe characters or patterns,
  # such as absolute paths or path traversal sequences (e.g., "..").
  class UnsafeNameError < Error
  end

  # Raised when {Writer#close} is called with unfilled placeholders.
  # All placeholders created via {Writer#reserve} must be filled before closing.
  class UnfilledPlaceholderError < Error
    def initialize(msg = "Unfilled placeholders remain")
      super
    end
  end

  # Raised when attempting to write more data than the declared size allows.
  class WriteOutOfRangeError < Error
    def initialize(msg = "Write exceeds allowed size")
      super
    end
  end

  # Raised when a numeric value is too large to encode in the tar header field.
  class ValueTooLargeError < Error
  end

  # Raised when a symlink or hardlink target exceeds the 100-byte limit.
  class LinkTargetTooLongError < Error
    def initialize(msg = "Link target exceeds 100 bytes")
      super
    end
  end
end
