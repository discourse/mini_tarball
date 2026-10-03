# frozen_string_literal: true

module MiniTarball
  # Manages placeholder reservations and fills within a tar archive.
  # @api private
  class PlaceholderManager
    # +dirty_bytes+ is the number of bytes at the start of the reserved space
    # that may not be NUL anymore.
    Reservation = Data.define(:name, :size, :header_start, :dirty_bytes)
    private_constant :Reservation

    # @param entry_guard [#call] runs the block that writes an entry, and raises
    #   if the writer can't start a new entry right now
    def initialize(io:, header_writer:, content_writer:, lookup:, entry_guard:)
      @io = io
      @header_writer = header_writer
      @content_writer = content_writer
      @lookup = lookup
      @entry_guard = entry_guard
      @reservations = {}
    end

    # Reserves space for a file to be filled later.
    #
    # @param name [String] filename in the archive
    # @param size [Integer] reserved size in bytes
    # @return [Placeholder]
    def reserve(name:, size:)
      header_start = @io.pos
      @header_writer.write(Header.new(name:, size:))

      # Seeking would leave a gap that doesn't grow the file, and SEEK_END would
      # then point into the space of the next placeholder.
      NullWriter.write(@io, size)
      @content_writer.write_padding(size)

      placeholder = Placeholder.new(name:, manager: self)
      @reservations[placeholder] = Reservation.new(name:, size:, header_start:, dirty_bytes: 0)
      placeholder
    end

    # Fills a placeholder with content from exactly one source.
    #
    # @param placeholder [Placeholder] the placeholder to fill
    # @param from [String, Pathname, nil] path to a regular file on disk
    # @param content [String, nil] string content
    # @param block [Proc, nil] block that streams the content
    # @param attribute_overrides [Hash] mode, uid, gid, uname, gname, mtime
    # @raise [IOError] if the writer is closed or another entry is still being written
    # @raise [WriteOutOfRangeError] if the content is larger than the reservation
    def fill(placeholder, from:, content:, block:, **attribute_overrides)
      reservation = find_reservation!(placeholder)

      @entry_guard.call do
        ContentSource.open(
          from:,
          content:,
          block:,
          lookup: @lookup,
          **attribute_overrides,
        ) { |source| write_content(placeholder:, reservation:, source:) }
      end
    end

    # @return [Boolean]
    def all_filled?
      @reservations.keys.all?(&:filled?)
    end

    private

    def find_reservation!(placeholder)
      raise IOError, "Writer is closed" if @io.respond_to?(:closed?) && @io.closed?

      reservation = @reservations[placeholder]
      raise ArgumentError, "Placeholder does not belong to this writer" unless reservation

      reservation
    end

    def write_content(placeholder:, reservation:, source:)
      ensure_fits!(reservation, source)

      # Encode first, so invalid attributes raise before the IO moves
      header_blocks =
        @header_writer.encode(
          Header.new(name: reservation.name, size: reservation.size, attrs: source.attrs),
        )

      stream = nil
      begin
        @io.seek(reservation.header_start)
        @io.write(header_blocks)
        ensure_header_rewritten!(reservation.header_start + header_blocks.bytesize)
        @content_writer.write_capped(
          size: reservation.size,
          pad_to: reservation.dirty_bytes,
        ) do |capped_stream|
          stream = capped_stream
          source.write_to(capped_stream)
        end
      ensure
        # When the padding failed, bytes of an earlier fill may still be there.
        if stream
          dirty_bytes = [stream.bytes_written, reservation.dirty_bytes].max
          @reservations[placeholder] = reservation.with(dirty_bytes:)
        end
        @io.seek(0, IO::SEEK_END)
      end
    end

    # Some IO wrappers don't move when seek is called. The header and content
    # would then end up at the end of the archive.
    def ensure_header_rewritten!(expected_pos)
      pos = @io.pos
      return if pos == expected_pos

      raise NotSeekableError,
            "IO did not seek to the header, so it can't be rewritten " \
              "(expected position #{expected_pos}, got #{pos})"
    end

    def ensure_fits!(reservation, source)
      return if source.size.nil? || source.size <= reservation.size

      raise WriteOutOfRangeError,
            "Content of #{source.size} bytes exceeds the reserved #{reservation.size} bytes"
    end
  end
end
