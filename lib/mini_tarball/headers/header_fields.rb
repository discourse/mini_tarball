# frozen_string_literal: true

module MiniTarball
  # Encodes header field values into binary format.
  #
  # @api private
  class HeaderFields
    FIELDS_LENGTH = Header::FIELDS.sum { |_, field| field[:length] }
    PACK_FORMAT =
      (
        Header::FIELDS.values.map { |field| "a#{field[:length]}" } +
          ["x#{Header::BLOCK_SIZE - FIELDS_LENGTH}"]
      ).join.freeze
    CHECKSUM_OFFSET = Header::FIELDS.take_while { |name, _| name != :checksum }.sum { _2[:length] }
    CHECKSUM_LENGTH = Header::FIELDS[:checksum][:length]
    private_constant :FIELDS_LENGTH, :PACK_FORMAT, :CHECKSUM_OFFSET, :CHECKSUM_LENGTH

    # @param header [Header] the header to encode
    def initialize(header)
      @header = header
    end

    # The checksum is computed with spaces in the checksum field. So the block
    # is packed once with spaces, and the checksum is written into it afterwards.
    #
    # @return [String] 512-byte binary header
    def to_binary
      values = Header::FIELDS.map { |name, field| encode_value(field, @header.value_of(name)) }
      block = values.pack(PACK_FORMAT)
      block.bytesplice(
        CHECKSUM_OFFSET,
        CHECKSUM_LENGTH,
        HeaderFormatter.format_checksum(block.sum(0)),
      )
    end

    private def encode_value(field, value)
      case field.fetch(:type)
      in :number
        HeaderFormatter.format_number(value, field.fetch(:length))
      in :mode
        HeaderFormatter.format_permissions(value, field.fetch(:length))
      in :checksum
        HeaderFormatter.format_checksum(nil)
      else
        value
      end
    end
  end
end
