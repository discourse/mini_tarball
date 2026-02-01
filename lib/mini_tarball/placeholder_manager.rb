# frozen_string_literal: true

module MiniTarball
  # Manages placeholder reservations and fills within a tar archive.
  # @api private
  class PlaceholderManager
    def initialize(io, header_writer, content_writer)
      @io = io
      @header_writer = header_writer
      @content_writer = content_writer
      @placeholders = []
    end

    # Reserves space for a file to be filled later.
    #
    # @param name [String] filename in the archive
    # @param size [Integer] reserved size in bytes
    # @return [Placeholder]
    def reserve(name:, size:)
      header_start = @io.pos
      @header_writer.write(Header.new(name:, size:))

      content_start = @io.pos
      @io.seek(size, IO::SEEK_CUR)
      @content_writer.write_padding

      placeholder = Placeholder.new(name:, size:, header_start:, content_start:, manager: self)
      @placeholders << placeholder
      placeholder
    end

    # Fills a placeholder with content.
    #
    # @param placeholder [Placeholder] the placeholder to fill
    # @param attrs [EntryAttributes] file attributes
    # @yieldparam stream [CappedWriteStream] stream to write content to
    def fill(placeholder, attrs, &block)
      ensure_placeholder_owned!(placeholder)

      @io.seek(placeholder.header_start)
      @header_writer.write(Header.new(name: placeholder.name, size: placeholder.size, attrs:))

      @io.seek(placeholder.content_start)
      begin
        @content_writer.write_capped(@io, size: placeholder.size, &block)
      ensure
        @io.seek(0, IO::SEEK_END)
      end
    end

    # Returns whether all placeholders have been filled.
    #
    # @return [Boolean]
    def all_filled?
      @placeholders.all?(&:filled?)
    end

    private

    def ensure_placeholder_owned!(placeholder)
      return if @placeholders.include?(placeholder)

      raise ArgumentError, "Placeholder does not belong to this writer"
    end
  end
end
