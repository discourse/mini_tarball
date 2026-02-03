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
    # @yieldparam stream [CappedWriteStream] stream to write content to
    def write_file(name, size, attrs, &block)
      @header_writer.write(Header.new(name:, size:, attrs:))
      begin
        write_capped(@io, size:, &block)
      ensure
        write_padding
      end
    end

    # Writes content with a size cap, padding remaining space with NUL bytes.
    #
    # @param target_io [IO] the IO to write to
    # @param size [Integer] maximum bytes to write
    # @yieldparam stream [CappedWriteStream] stream to write content to
    def write_capped(target_io, size:)
      capped_stream = CappedWriteStream.new(target_io, max_size: size)

      begin
        yield capped_stream
      ensure
        remaining_bytes = capped_stream.remaining
        NullWriter.write(target_io, remaining_bytes) if remaining_bytes > 0
      end
    end

    # Writes NUL padding to align to the next block boundary.
    def write_padding
      padding_length = (Header::BLOCK_SIZE - @io.pos) % Header::BLOCK_SIZE
      NullWriter.write(@io, padding_length)
    end
  end
end
