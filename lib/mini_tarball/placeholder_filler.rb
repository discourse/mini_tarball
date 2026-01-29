# frozen_string_literal: true

module MiniTarball
  # A restricted writer interface used when filling placeholders.
  # Yielded by {Writer#fill} to prevent operations that would corrupt the archive.
  #
  # Only file-adding methods are available; structural operations like
  # {Writer#reserve}, {Writer#add_directory}, and {Writer#close} are not exposed.
  #
  # @example Filling a placeholder
  #   writer.fill(placeholder) do |filler|
  #     filler.add_file(name: "data.txt", source_file_path: "/tmp/data.txt")
  #   end
  #
  # @see Writer#fill
  # @see Writer#reserve
  class PlaceholderFiller
    # @api private
    def initialize(writer)
      @writer = writer
    end

    # (see Writer#add_file)
    # @return [self]
    def add_file(...)
      @writer.add_file(...)
      self
    end

    # (see Writer#add_file_from_stream)
    # @return [self]
    def add_file_from_stream(...)
      @writer.add_file_from_stream(...)
      self
    end
  end
end
