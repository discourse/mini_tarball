# frozen_string_literal: true

module MiniTarball
  # Content of a file entry from one of three sources: a file on disk
  # (+from:+), a String (+content:+) or a block. Writer#file and
  # Placeholder#fill both use it, so both handle sources the same way.
  #
  # @api private
  class ContentSource
    # @return [EntryAttributes] attributes for the entry header
    attr_reader :attrs

    # @return [Integer, nil] content size, or nil if a block streams an unknown amount
    attr_reader :size

    # Resolves the content source and yields it.
    #
    # @param from [String, #to_path, nil] path to a regular file on disk
    # @param content [String, nil] string content
    # @param block [Proc, nil] block that streams the content
    # @param lookup [#username, #groupname] resolves owner IDs of files on disk
    # @param attribute_overrides [Hash] mode, uid, gid, uname, gname, mtime
    # @yieldparam source [ContentSource]
    # @return [Object] the block's result
    # @raise [ArgumentError] if not exactly one source is given, or +from:+ isn't a regular file
    # @raise [FileChangedError] from #write_to if the +from:+ file changes its size after it was opened
    def self.open(from:, content:, block:, lookup:, **attribute_overrides, &)
      SourceValidator.validate!(from:, content:, block:)
      return open_file(from, lookup:, **attribute_overrides, &) if from

      attrs = EntryAttributes.with_file_defaults(**attribute_overrides)
      if content
        yield new(attrs:, size: content.bytesize) { |stream| stream.write(content) }
      else
        yield new(attrs:, size: nil, &block)
      end
    end

    # Opens the file once and uses fstat, so size and attributes belong to the
    # content that is read. Only regular files are allowed, because the size
    # of a directory or device isn't its content.
    #
    # The path is checked before it is opened, because opening a FIFO waits
    # until another process opens it for writing. The path can change between
    # the check and the open, so the open file is checked again.
    private_class_method def self.open_file(from, lookup:, **attribute_overrides)
      path = File.path(from)
      ensure_regular_file!(File.stat(path), path)

      File.open(path, "rb") do |file|
        stat = file.stat
        ensure_regular_file!(stat, path)

        attrs = EntryAttributes.from_stat(stat, lookup:, **attribute_overrides)
        size = stat.size
        yield new(attrs:, size:) { |stream| copy_file(file, stream, size:) }
      end
    end

    private_class_method def self.ensure_regular_file!(stat, path)
      raise ArgumentError, "from: must be a regular file: #{path}" unless stat.file?
    end

    # The header already has the size, so a file that grew or shrank since
    # then would give a cut off or broken entry.
    private_class_method def self.copy_file(file, stream, size:)
      copied = IO.copy_stream(file, stream, size)
      return if copied == size && file.eof?

      raise FileChangedError,
            "#{file.path} changed while it was being archived (expected #{size} bytes)"
    end

    # @api private
    def initialize(attrs:, size:, &writer)
      @attrs = attrs
      @size = size
      @writer = writer
    end

    # @param stream [#write] the destination
    # @return [void]
    def write_to(stream)
      @writer.call(stream)
    end
  end
end
