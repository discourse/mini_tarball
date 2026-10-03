# frozen_string_literal: true

module MiniTarball
  # Mode, owner and modification time of an entry.
  #
  # @api private
  EntryAttributes =
    Data.define(:mode, :uid, :gid, :uname, :gname, :mtime) do
      # @raise [ArgumentError] if mode, uid or gid isn't a non-negative Integer,
      #   uname or gname can't be stored in the header, or mtime isn't a Time
      #   or an Integer
      def initialize(mode:, uid:, gid:, uname:, gname:, mtime:)
        EntryAttributes.validate_number!(mode, label: "mode")
        EntryAttributes.validate_number!(uid, label: "uid")
        EntryAttributes.validate_number!(gid, label: "gid")
        OwnerNameValidator.validate!(uname, label: "uname")
        OwnerNameValidator.validate!(gname, label: "gname")
        EntryAttributes.validate_mtime!(mtime)
        super
      end

      # @param value [Object] the value to check; nil means "not set"
      # @param label [String] attribute name for error messages
      # @return [void]
      # @raise [ArgumentError] if the value isn't nil or a non-negative Integer
      def self.validate_number!(value, label:)
        return if value.nil? || (value.is_a?(Integer) && value >= 0)

        raise ArgumentError, "#{label} must be a non-negative Integer: #{value.inspect}"
      end

      # @param value [Object] the modification time to check; nil means "not set"
      # @return [void]
      # @raise [ArgumentError] if the value isn't nil, a Time or an Integer
      def self.validate_mtime!(value)
        case value
        when NilClass, Time, Integer
          nil
        else
          raise ArgumentError, "mtime must be a Time or an Integer: #{value.inspect}"
        end
      end

      # Creates attributes and uses the default for every nil value, so
      # +mode: nil+ works the same as leaving out +mode:+.
      #
      # @param default_mode [Integer] mode used when +mode+ is nil
      # @param mode [Integer, nil] permissions
      # @param uid [Integer, nil] owner user ID
      # @param gid [Integer, nil] group ID
      # @param uname [String, nil] owner username (default: "nobody")
      # @param gname [String, nil] group name (default: "nogroup")
      # @param mtime [Time, Integer, nil] modification time
      # @return [EntryAttributes]
      def self.with_defaults(
        default_mode:,
        mode: nil,
        uid: nil,
        gid: nil,
        uname: nil,
        gname: nil,
        mtime: nil
      )
        new(
          mode: mode || default_mode,
          uid:,
          gid:,
          uname: uname || UserGroupLookup::DEFAULT_UNAME,
          gname: gname || UserGroupLookup::DEFAULT_GNAME,
          mtime:,
        )
      end

      # Creates attributes with the defaults for files.
      #
      # @param mode [Integer, nil] file permissions (default: 0644)
      # @param uid [Integer, nil] owner user ID
      # @param gid [Integer, nil] group ID
      # @param uname [String, nil] owner username (default: "nobody")
      # @param gname [String, nil] group name (default: "nogroup")
      # @param mtime [Time, Integer, nil] modification time
      # @return [EntryAttributes]
      def self.with_file_defaults(mode: nil, uid: nil, gid: nil, uname: nil, gname: nil, mtime: nil)
        with_defaults(default_mode: 0644, mode:, uid:, gid:, uname:, gname:, mtime:)
      end

      # Creates attributes from a File::Stat object with optional overrides.
      #
      # If +uid:+ or +gid:+ is given, uname and gname are looked up for those
      # IDs and not for the file owner.
      #
      # @param stat [File::Stat] the file statistics
      # @param lookup [#username, #groupname] resolves IDs to names
      # @param mode [Integer, nil] override mode (default: from stat)
      # @param uid [Integer, nil] override user ID (default: from stat)
      # @param gid [Integer, nil] override group ID (default: from stat)
      # @param uname [String, nil] override username (default: looked up from the uid)
      # @param gname [String, nil] override group name (default: looked up from the gid)
      # @param mtime [Time, Integer, nil] override modification time (default: from stat)
      # @return [EntryAttributes]
      # @raise [ArgumentError] if an attribute is invalid
      def self.from_stat(
        stat,
        lookup: UserGroupLookup,
        mode: nil,
        uid: nil,
        gid: nil,
        uname: nil,
        gname: nil,
        mtime: nil
      )
        uid ||= stat.uid
        gid ||= stat.gid
        # Check the IDs before the name lookup, so wrong values get the same
        # error as in #initialize.
        validate_number!(uid, label: "uid")
        validate_number!(gid, label: "gid")

        new(
          mode: mode || stat.mode,
          uid:,
          gid:,
          uname: uname || lookup.username(uid),
          gname: gname || lookup.groupname(gid),
          mtime: mtime || stat.mtime,
        )
      end
    end
end
