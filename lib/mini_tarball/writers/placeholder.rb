# frozen_string_literal: true

module MiniTarball
  # Represents a reserved space in the archive that can be filled later.
  # This object is just a handle; it exposes the name but not the size.
  # Use {#fill} to write content.
  #
  # Placeholders are created via {Writer#placeholder} and filled via {#fill}.
  # This allows writing a file entry at a specific position in the archive
  # while deferring the actual content until later.
  #
  # @example
  #   Writer.create("archive.tar") do |w|
  #     manifest = w.placeholder "manifest.json", size: 4096
  #     w.file "data.bin", from: "data.bin"
  #     manifest.fill content: JSON.generate(files: ["data.bin"])
  #   end
  class Placeholder
    # @return [String] the filename in the archive
    attr_reader :name

    # @api private
    def initialize(name:, manager:)
      @name = name
      @manager = manager
      @filled = false
    end

    # Fills the placeholder with content.
    #
    # Exactly one content source must be provided:
    # - +from:+ to copy from a file on disk
    # - +content:+ to write a string directly
    # - A block to stream content
    #
    # @example Fill from string
    #   placeholder.fill content: "hello world"
    #
    # @example Fill from file
    #   placeholder.fill from: "path/to/file.txt"
    #
    # @example Fill via streaming
    #   placeholder.fill do |stream|
    #     stream.write("generated content")
    #   end
    #
    # @param from [String, Pathname, nil] path to source file on disk
    # @param content [String, nil] string content to write
    # @param mode [Integer, nil] file permissions
    # @param uid [Integer, nil] owner user ID
    # @param gid [Integer, nil] group ID
    # @param uname [String, nil] owner username
    # @param gname [String, nil] group name
    # @param mtime [Time, Integer, nil] modification time
    # @return [self]
    # @raise [IOError] if the writer is closed
    # @raise [ArgumentError] if already filled, invalid content source, or +from:+ isn't a regular file
    # @raise [WriteOutOfRangeError] if content exceeds reserved size
    # @raise [FileChangedError] if the +from:+ file changes its size while it is copied
    # @raise [ValueTooLargeError] if numeric values exceed tar header limits
    # @raise [NotSeekableError] if the IO didn't seek back to the header
    def fill(
      from: nil,
      content: nil,
      mode: nil,
      uid: nil,
      gid: nil,
      uname: nil,
      gname: nil,
      mtime: nil,
      &block
    )
      raise ArgumentError, "Placeholder already filled" if @filled

      @manager.fill(self, from:, content:, block:, mode:, uid:, gid:, uname:, gname:, mtime:)

      @filled = true
      self
    end

    # @return [Boolean] whether this placeholder has been filled
    def filled?
      @filled
    end
  end
end
