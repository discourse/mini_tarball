# frozen_string_literal: true

module MiniTarball
  module Headers
    # Defines the tar header field layout and derived metadata.
    #
    # @api private
    module Layout
      FIELDS =
        [
          [:name, 100, :chars],
          [:mode, 8, :mode],
          [:uid, 8, :number],
          [:gid, 8, :number],
          [:size, 12, :number],
          [:mtime, 12, :number],
          [:checksum, 8, :checksum],
          [:typeflag, 1, :chars],
          [:linkname, 100, :chars],
          [:magic, 6, :chars],
          [:version, 2, :chars],
          [:uname, 32, :chars],
          [:gname, 32, :chars],
          [:devmajor, 8, :number],
          [:devminor, 8, :number],
          [:prefix, 155, :chars],
        ].map(&:freeze).freeze

      FIELD_MAP =
        begin
          offset = 0
          fields = {}
          FIELDS.each do |name, length, type|
            fields[name] = { length: length, type: type, offset: offset }.freeze
            offset += length
          end
          fields.freeze
        end

      PACK_FORMAT = FIELDS.map { |(_, length, _)| "a#{length}" }.join("").freeze
      TOTAL_SIZE = FIELDS.sum { |(_, length, _)| length }
    end
  end
end
