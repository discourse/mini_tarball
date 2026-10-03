# frozen_string_literal: true

module MiniTarball
  # Writes file entries: header, size-capped content and block padding.
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
    def write_file(name:, size:, attrs:, allow_short_writes: false, &block)
      @header_writer.write(Header.new(name:, size:, attrs:))
      begin
        stream = write_capped(size:, &block)
        ensure_declared_size_written!(stream, size) unless allow_short_writes
      ensure
        write_padding(size)
      end
    end

    # Writes content at the current position with a size cap.
    #
    # After the block, writes NUL bytes until +pad_to+ bytes are written, also
    # when the block raises. Placeholders pass a smaller +pad_to+, because their
    # space already contains NUL bytes.
    #
    # @param size [Integer] maximum bytes to write
    # @param pad_to [Integer] write NULs from the end of the content up to this many bytes
    # @yieldparam stream [CappedWriteStream] stream to write content to
    # @return [CappedWriteStream] the stream after the block ran
    def write_capped(size:, pad_to: size)
      capped_stream = CappedWriteStream.new(@io, max_size: size)

      begin
        yield capped_stream
      ensure
        NullWriter.write(@io, pad_to - capped_stream.bytes_written)
      end

      capped_stream
    end

    # Writes NUL bytes after content of the given size, up to the next block boundary.
    #
    # @param content_size [Integer] size of the entry's content in bytes
    def write_padding(content_size)
      NullWriter.write(@io, -content_size % Header::BLOCK_SIZE)
    end

    private

    def ensure_declared_size_written!(stream, size)
      return if stream.remaining == 0

      raise IncompleteWriteError,
            "Entry declared #{size} bytes but only #{stream.bytes_written} were written"
    end
  end
end
