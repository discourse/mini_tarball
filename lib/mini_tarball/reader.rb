# frozen_string_literal: true

module MiniTarball
  class Reader
    def self.use(io)
      reader = new(io)
      yield reader
    ensure
      reader&.close
    end

    def initialize(io)
      @io = io
      @closed = false
    end

    def each_entry
      return enum_for(:each_entry) unless block_given?

      ensure_not_closed

      loop do
        header_data = @io.read(Header::BLOCK_SIZE)
        break if header_data.nil?

        values = HeaderParser.parse(header_data)
        break if values.nil? # End of archive or invalid

        entry = Entry.new(values)

        # Handle GNU long link for long filenames
        if values[:typeflag] == "L" # TYPE_LONG_LINK
          long_name = read_content(values[:size]).delete("\0")
          skip_padding(values[:size])

          # Read the actual entry header
          header_data = @io.read(Header::BLOCK_SIZE)
          break if header_data.nil?

          values = HeaderParser.parse(header_data)
          break if values.nil?

          values[:name] = long_name
          entry = Entry.new(values)
        end

        content_stream = BoundedReadStream.new(@io, size: entry.size)
        yield entry, content_stream

        # Skip any unread content and padding
        skip_remaining(content_stream.remaining)
        skip_padding(entry.size)
      end

      self
    end

    def close
      ensure_not_closed
      @closed = true
    end

    private

    def ensure_not_closed
      raise "Reader is already closed" if @closed
    end

    def read_content(size)
      @io.read(size)
    end

    def skip_remaining(bytes)
      @io.read(bytes) if bytes > 0
    end

    def skip_padding(content_size)
      padding = (Header::BLOCK_SIZE - (content_size % Header::BLOCK_SIZE)) % Header::BLOCK_SIZE
      @io.read(padding) if padding > 0
    end
  end
end
