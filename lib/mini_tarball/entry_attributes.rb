# frozen_string_literal: true

module MiniTarball
  # Immutable value object representing tar entry metadata.
  #
  # Used internally by Writer to consolidate file attributes (mode, ownership,
  # timestamps) that would otherwise be passed as multiple parameters.
  #
  # @api private
  EntryAttributes =
    Data.define(:mode, :uid, :gid, :uname, :gname, :mtime) do
      # Creates attributes with sensible defaults for file entries.
      #
      # @param mode [Integer, nil] file permissions (default: 0644)
      # @param uid [Integer, nil] owner user ID
      # @param gid [Integer, nil] group ID
      # @param uname [String, nil] owner username (default: "nobody")
      # @param gname [String, nil] group name (default: "nogroup")
      # @param mtime [Time, nil] modification time
      # @return [EntryAttributes]
      def self.with_file_defaults(mode: nil, uid: nil, gid: nil, uname: nil, gname: nil, mtime: nil)
        new(
          mode: mode || 0644,
          uid:,
          gid:,
          uname: uname || "nobody",
          gname: gname || "nogroup",
          mtime:,
        )
      end

      # Creates attributes from a File::Stat object with optional overrides.
      #
      # @param stat [File::Stat] the file statistics
      # @param mode [Integer, nil] override mode (default: from stat)
      # @param uid [Integer, nil] override user ID (default: from stat)
      # @param gid [Integer, nil] override group ID (default: from stat)
      # @param uname [String, nil] override username (default: looked up from stat.uid)
      # @param gname [String, nil] override group name (default: looked up from stat.gid)
      # @param mtime [Time, nil] override modification time (default: from stat)
      # @return [EntryAttributes]
      def self.from_stat(stat, mode: nil, uid: nil, gid: nil, uname: nil, gname: nil, mtime: nil)
        new(
          mode: mode || stat.mode,
          uid: uid || stat.uid,
          gid: gid || stat.gid,
          uname: uname || UserGroupLookup.username(stat.uid),
          gname: gname || UserGroupLookup.groupname(stat.gid),
          mtime: mtime || stat.mtime,
        )
      end
    end
end
