# frozen_string_literal: true

module MiniTarball
  # Read-only metadata for a tar archive entry.
  #
  # Entry objects are yielded by {Reader#each_entry} and provide access to
  # all header fields plus type predicates for common entry types.
  #
  # @example Iterating over entries
  #   Reader.open("archive.tar") do |reader|
  #     reader.each_entry do |entry, stream|
  #       puts "#{entry.name} (#{entry.size} bytes)" if entry.file?
  #     end
  #   end
  Entry =
    Data.define(
      :name,
      :mode,
      :uid,
      :gid,
      :size,
      :mtime,
      :typeflag,
      :linkname,
      :uname,
      :gname,
      :devmajor,
      :devminor,
    ) do
      # Creates an Entry from a parsed header, with optional pax attribute overrides.
      #
      # @param header [HeaderParser::ParsedHeader] the parsed tar header
      # @param pax_attributes [Hash, nil] pax extended attributes to override header values
      # @return [Entry]
      def self.from_header(header, pax_attributes: nil)
        pax = pax_attributes || {}

        new(
          name: pax["path"] || header.full_name,
          mode: header.mode,
          uid: pax["uid"]&.to_i || header.uid,
          gid: pax["gid"]&.to_i || header.gid,
          size: pax["size"]&.to_i || header.size,
          mtime: parse_mtime(pax["mtime"], header.mtime),
          typeflag: header.typeflag,
          linkname: pax["linkpath"] || header.linkname,
          uname: pax["uname"] || header.uname,
          gname: pax["gname"] || header.gname,
          devmajor: header.devmajor,
          devminor: header.devminor,
        )
      end

      # Returns whether this entry is a regular file.
      # @return [Boolean]
      def file?
        typeflag == Header::TYPE_REGULAR || typeflag == "\0"
      end

      # Returns whether this entry is a directory.
      # @return [Boolean]
      def directory?
        typeflag == Header::TYPE_DIRECTORY
      end

      # Returns whether this entry is a symbolic link.
      # @return [Boolean]
      def symlink?
        typeflag == Header::TYPE_SYMLINK
      end

      # Returns whether this entry is a hard link.
      # @return [Boolean]
      def hardlink?
        typeflag == Header::TYPE_HARDLINK
      end

      # Returns whether this entry is a link (symlink or hardlink).
      # @return [Boolean]
      def link?
        symlink? || hardlink?
      end

      # Returns whether this is a pax extended header entry.
      # @return [Boolean]
      def pax_extended?
        typeflag == Header::TYPE_PAX_EXTENDED
      end

      # Returns whether this is a pax global header entry.
      # @return [Boolean]
      def pax_global?
        typeflag == Header::TYPE_PAX_GLOBAL
      end

      # Returns whether this is a GNU long link header.
      # @return [Boolean]
      def gnu_long_link?
        typeflag == "L"
      end

      # Returns whether this is a GNU long linkname header.
      # @return [Boolean]
      def gnu_long_linkname?
        typeflag == "K"
      end

      # Returns whether this is a metadata entry (not a real file/dir/link).
      # @return [Boolean]
      def metadata?
        pax_extended? || pax_global? || gnu_long_link? || gnu_long_linkname?
      end

      private

      def self.parse_mtime(pax_mtime, header_mtime)
        if pax_mtime
          # Pax mtime can be a decimal (seconds with nanosecond precision)
          seconds, nanoseconds = pax_mtime.split(".")
          time = Time.at(seconds.to_i).utc
          if nanoseconds
            # Ruby Time.at can accept a Rational for subsecond precision
            time = Time.at(Rational("#{seconds}.#{nanoseconds}".to_r)).utc
          end
          time
        else
          Time.at(header_mtime).utc
        end
      end
    end
end
