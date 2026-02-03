# frozen_string_literal: true

require "etc"

module MiniTarball
  # Looks up usernames and group names from system databases.
  # Falls back to defaults when IDs are not found.
  #
  # @api private
  module UserGroupLookup
    DEFAULT_UNAME = "nobody"
    DEFAULT_GNAME = "nogroup"
    private_constant :DEFAULT_UNAME, :DEFAULT_GNAME

    # Returns the username for a user ID.
    #
    # @param uid [Integer] the user ID
    # @return [String] username, or "nobody" if not found
    def self.username(uid)
      Etc.getpwuid(uid).name
    rescue ArgumentError
      DEFAULT_UNAME
    end

    # Returns the group name for a group ID.
    #
    # @param gid [Integer] the group ID
    # @return [String] group name, or "nogroup" if not found
    def self.groupname(gid)
      Etc.getgrgid(gid).name
    rescue ArgumentError
      DEFAULT_GNAME
    end
  end
end
