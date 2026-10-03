# frozen_string_literal: true

require "etc"

module MiniTarball
  # Looks up usernames and group names from system databases.
  # Leaves names empty when IDs are not found so extractors use the numeric IDs.
  # IDs that are too large for the system lookup are treated as not found.
  # The header can still store them.
  #
  # @api private
  module UserGroupLookup
    DEFAULT_UNAME = "nobody"
    DEFAULT_GNAME = "nogroup"

    # @param uid [Integer] the user ID
    # @return [String] username, or "" if not found or it doesn't fit the header
    def self.username(uid)
      # Returns nil on some platforms, e.g. Windows
      storable_name(Etc.getpwuid(uid)&.name)
    rescue ArgumentError, RangeError
      ""
    end

    # @param gid [Integer] the group ID
    # @return [String] group name, or "" if not found or it doesn't fit the header
    def self.groupname(gid)
      storable_name(Etc.getgrgid(gid)&.name)
    rescue ArgumentError, RangeError
      ""
    end

    # Names that don't fit the 32-byte header field are stored empty. GNU tar
    # then uses the numeric ID. A cut off name or "nobody" could give the file
    # the wrong owner.
    private_class_method def self.storable_name(name)
      OwnerNameValidator.valid?(name) ? name : ""
    end

    # Caches lookups for one writer. Without it, every file from disk needs
    # two lookups in the passwd and group databases, which can be slow with
    # LDAP or NIS. The cache isn't shared between writers, because names can
    # change while a process runs.
    class Cache
      def initialize
        @usernames = {}
        @groupnames = {}
      end

      # @param uid [Integer] the user ID
      # @return [String] username, or "" if not found or it doesn't fit the header
      def username(uid)
        @usernames.fetch(uid) { @usernames[uid] = UserGroupLookup.username(uid) }
      end

      # @param gid [Integer] the group ID
      # @return [String] group name, or "" if not found or it doesn't fit the header
      def groupname(gid)
        @groupnames.fetch(gid) { @groupnames[gid] = UserGroupLookup.groupname(gid) }
      end
    end
  end
end
