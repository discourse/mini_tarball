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

  # Raised when a seekable IO is required but the provided IO doesn't support seeking
  # or is in append mode. This occurs when using {Writer#file} with a block but
  # without a size parameter, or when using {Writer#placeholder}.
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
  end

  # Raised when a streamed entry writes fewer bytes than its declared size.
  class IncompleteWriteError < Error
  end

  # Raised when a file from disk has a different size while it's copied than
  # when its header was written.
  class FileChangedError < Error
  end

  # Raised when a numeric value is too large to encode in the tar header field.
  class ValueTooLargeError < Error
  end
end
