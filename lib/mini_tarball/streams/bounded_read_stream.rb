# frozen_string_literal: true

module MiniTarball
  # A read-only stream that limits reads to a specified size.
  # Compatible with IO.copy_stream and most upload SDKs (AWS S3, GCS, etc.)
  #
  # @example Streaming to S3
  #   Reader.use(tar_io) do |reader|
  #     reader.each_entry do |entry, stream|
  #       next unless entry.file?
  #       s3.put_object(bucket: "bucket", key: entry.name, body: stream)
  #     end
  #   end
  class BoundedReadStream
    attr_reader :size, :remaining

    def initialize(io, size:)
      @io = io
      @size = size
      @remaining = size
    end

    def read(length = nil, buffer = nil)
      return nil if @remaining == 0

      length = @remaining if length.nil? || length > @remaining
      data = @io.read(length, buffer)
      @remaining -= data.bytesize if data
      data
    end

    def eof?
      @remaining == 0
    end

    # Bytes read so far
    def pos
      @size - @remaining
    end

    alias_method :tell, :pos
  end
end
