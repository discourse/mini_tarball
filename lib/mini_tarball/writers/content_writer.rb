# frozen_string_literal: true

module MiniTarball
  # Handles writing file content to the archive with size limits and padding.
  # @api private
  class ContentWriter
    def initialize(io, header_writer)
      @io = io
      @header_writer = header_writer
    end

    # Writes a file entry with known size.
    #
    # @param name [String] filename in the archive
    # @param size [Integer] content size in bytes
    # @param attrs [EntryAttributes] file attributes
    # @param allow_short_writes [Boolean] NUL-pad instead of raising when the
    #   block writes fewer than +size+ bytes
    # @yieldparam stream [CappedWriteStream] stream to write content to
    # @raise [IncompleteWriteError] if the block writes fewer than +size+ bytes
    #   and +allow_short_writes+ is false
    def write_file(name, size, attrs, allow_short_writes: false, &block)
      @header_writer.write(Header.new(name:, size:, attrs:))
      begin
        stream = write_capped(@io, size:, &block)
        ensure_declared_size_written!(stream, size) unless allow_short_writes
      ensure
        write_padding
      end
    end

    # Writes content with a size cap, padding remaining space with NUL bytes.
    # Padding on short writes is intentional here: placeholders reserve more
    # space than their fill content may use.
    #
    # @param target_io [IO] the IO to write to
    # @param size [Integer] maximum bytes to write
    # @yieldparam stream [CappedWriteStream] stream to write content to
    # @return [CappedWriteStream] the stream after the block ran
    def write_capped(target_io, size:)
      capped_stream = CappedWriteStream.new(target_io, max_size: size)

      begin
        yield capped_stream
      ensure
        remaining_bytes = capped_stream.remaining
        NullWriter.write(target_io, remaining_bytes) if remaining_bytes > 0
      end

      capped_stream
    end

    # Writes NUL padding to align to the next block boundary.
    def write_padding
      padding_length = Header.padding_for(@io.pos)
      NullWriter.write(@io, padding_length)
    end

    private

    def ensure_declared_size_written!(stream, size)
      return if stream.remaining == 0

      raise IncompleteWriteError,
            "Entry declared #{size} bytes but only #{stream.bytes_written} were written"
    end
  end
end
