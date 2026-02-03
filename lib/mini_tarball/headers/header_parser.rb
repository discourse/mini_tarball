# frozen_string_literal: true

module MiniTarball
  # Parses binary tar headers into structured data.
  #
  # Supports GNU tar, POSIX ustar, and pax formats. Handles both octal
  # and base-256 encoded numeric fields.
  #
  # @api private
  module HeaderParser
    BLOCK_SIZE = Header::BLOCK_SIZE
    NULL_BLOCK = ("\0" * BLOCK_SIZE).b.freeze

    # Field offsets and lengths in the tar header
    FIELD_OFFSETS = {
      name: {
        offset: 0,
        length: 100,
      },
      mode: {
        offset: 100,
        length: 8,
      },
      uid: {
        offset: 108,
        length: 8,
      },
      gid: {
        offset: 116,
        length: 8,
      },
      size: {
        offset: 124,
        length: 12,
      },
      mtime: {
        offset: 136,
        length: 12,
      },
      checksum: {
        offset: 148,
        length: 8,
      },
      typeflag: {
        offset: 156,
        length: 1,
      },
      linkname: {
        offset: 157,
        length: 100,
      },
      magic: {
        offset: 257,
        length: 6,
      },
      version: {
        offset: 263,
        length: 2,
      },
      uname: {
        offset: 265,
        length: 32,
      },
      gname: {
        offset: 297,
        length: 32,
      },
      devmajor: {
        offset: 329,
        length: 8,
      },
      devminor: {
        offset: 337,
        length: 8,
      },
      prefix: {
        offset: 345,
        length: 155,
      },
    }.freeze

    # Parsed header data
    ParsedHeader =
      Data.define(
        :name,
        :mode,
        :uid,
        :gid,
        :size,
        :mtime,
        :checksum,
        :typeflag,
        :linkname,
        :magic,
        :version,
        :uname,
        :gname,
        :devmajor,
        :devminor,
        :prefix,
      ) do
        # Returns the full path by combining prefix and name.
        # @return [String]
        def full_name
          prefix && !prefix.empty? ? "#{prefix}/#{name}" : name
        end

        # Returns whether this is a GNU tar format header.
        # @return [Boolean]
        def gnu_format?
          magic == "ustar " || magic == "ustar"
        end

        # Returns whether this is a POSIX ustar format header.
        # @return [Boolean]
        def ustar_format?
          magic&.start_with?("ustar\0") || magic == "ustar"
        end
      end

    class << self
      # Parses a 512-byte binary header block.
      #
      # @param data [String] exactly 512 bytes of binary header data
      # @param verify_checksum [Boolean] whether to verify the checksum
      # @return [ParsedHeader, nil] parsed header or nil if end-of-archive
      # @raise [InvalidHeaderError] if header is malformed
      # @raise [ChecksumMismatchError] if checksum verification fails
      def parse(data, verify_checksum: true)
        if data.bytesize != BLOCK_SIZE
          raise InvalidHeaderError, "Header must be #{BLOCK_SIZE} bytes"
        end

        return nil if null_block?(data)

        verify_checksum!(data) if verify_checksum

        ParsedHeader.new(
          name: extract_string(:name, data),
          mode: extract_number(:mode, data),
          uid: extract_number(:uid, data),
          gid: extract_number(:gid, data),
          size: extract_number(:size, data),
          mtime: extract_number(:mtime, data),
          checksum: extract_number(:checksum, data),
          typeflag: extract_typeflag(data),
          linkname: extract_string(:linkname, data),
          magic: extract_raw(:magic, data),
          version: extract_raw(:version, data),
          uname: extract_string(:uname, data),
          gname: extract_string(:gname, data),
          devmajor: extract_number(:devmajor, data),
          devminor: extract_number(:devminor, data),
          prefix: extract_string(:prefix, data),
        )
      end

      # Checks if a block is a null block (end-of-archive marker).
      #
      # @param data [String] the block to check
      # @return [Boolean]
      def null_block?(data)
        data == NULL_BLOCK
      end

      # Computes the checksum for a header block.
      # The checksum field is treated as 8 spaces for computation.
      #
      # @param data [String] the 512-byte header block
      # @return [Integer] the computed checksum
      def compute_checksum(data)
        checksum_offset = FIELD_OFFSETS[:checksum][:offset]
        checksum_length = FIELD_OFFSETS[:checksum][:length]

        sum = 0
        data.each_byte.with_index do |byte, index|
          sum +=
            if index >= checksum_offset && index < checksum_offset + checksum_length
              32 # space character
            else
              byte
            end
        end
        sum
      end

      private

      def verify_checksum!(data)
        stored = extract_number(:checksum, data)
        computed = compute_checksum(data)

        return if stored == computed

        # Also try signed checksum (some old implementations)
        signed_computed = compute_signed_checksum(data)
        return if stored == signed_computed

        raise ChecksumMismatchError.new(expected: stored, actual: computed)
      end

      def compute_signed_checksum(data)
        checksum_offset = FIELD_OFFSETS[:checksum][:offset]
        checksum_length = FIELD_OFFSETS[:checksum][:length]

        sum = 0
        data.each_byte.with_index do |byte, index|
          if index >= checksum_offset && index < checksum_offset + checksum_length
            sum += 32
          elsif byte > 127
            sum += byte - 256
          else
            sum += byte
          end
        end
        sum
      end

      def extract_string(field, data)
        raw = extract_raw(field, data)
        # Strings are null-terminated
        null_index = raw.index("\0")
        str = null_index ? raw[0, null_index] : raw
        str.force_encoding(Encoding::UTF_8)
        str.valid_encoding? ? str : str.force_encoding(Encoding::BINARY)
      end

      def extract_raw(field, data)
        info = FIELD_OFFSETS[field]
        data.byteslice(info[:offset], info[:length])
      end

      def extract_typeflag(data)
        raw = extract_raw(:typeflag, data)
        # Empty typeflag is treated as regular file ('0')
        raw == "\0" ? "0" : raw
      end

      def extract_number(field, data)
        raw = extract_raw(field, data)
        parse_number(raw)
      end

      def parse_number(raw)
        return 0 if raw.nil? || raw.empty?

        first_byte = raw.getbyte(0)

        # Base-256 encoded (high bit set)
        return parse_base256(raw) if first_byte & 0x80 != 0

        # Octal encoded - strip trailing nulls and spaces
        str = raw.gsub(/[\0 ]+\z/, "")
        return 0 if str.empty?

        Integer(str, 8)
      rescue ArgumentError
        raise InvalidHeaderError, "Invalid octal number: #{raw.inspect}"
      end

      def parse_base256(raw)
        # First byte has 0x80 set to indicate base-256
        # Can also be 0xFF for negative (not supported)
        first_byte = raw.getbyte(0)
        raise InvalidHeaderError, "Negative base-256 not supported" if first_byte == 0xFF

        value = 0
        raw.bytes[1..].each { |byte| value = (value << 8) | byte }
        value
      end
    end
  end
end
