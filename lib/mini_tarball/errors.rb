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
  # This occurs when using {Writer#file} with a block but without a size parameter,
  # or when using {Writer#placeholder}.
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
  # All placeholders created via {Writer#placeholder} must be filled before closing.
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

  # Raised when a streamed entry writes fewer bytes than its declared size.
  class IncompleteWriteError < Error
  end

  # Raised when a numeric value is too large to encode in the tar header field.
  class ValueTooLargeError < Error
  end

  # Raised when an extraction path would escape the destination directory.
  class PathTraversalError < Error
  end

  # Raised when reading a tar archive that is incomplete or corrupted.
  class TruncatedArchiveError < Error
    def initialize(msg = "Archive is truncated or incomplete")
      super
    end
  end

  # Raised when a tar header cannot be parsed.
  class InvalidHeaderError < Error
  end

  # Raised when a tar header checksum does not match.
  class ChecksumMismatchError < InvalidHeaderError
    def initialize(expected:, actual:)
      super("Checksum mismatch: expected #{expected}, got #{actual}")
    end
  end

  # Raised when archive limits are exceeded (max file size, total size, entry count).
  class ArchiveLimitError < Error
  end
end
