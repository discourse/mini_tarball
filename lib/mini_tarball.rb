# frozen_string_literal: true

# Core
require "mini_tarball/errors"
require "mini_tarball/version"

# Shared data structures (load order matters: entry_attributes before header)
require "mini_tarball/writers/entry_attributes"

# Headers
require "mini_tarball/headers/user_group_lookup"
require "mini_tarball/headers/header"
require "mini_tarball/headers/header_fields"
require "mini_tarball/headers/header_formatter"
require "mini_tarball/headers/header_writer"

# Streams
require "mini_tarball/streams/capped_write_stream"
require "mini_tarball/streams/write_only_stream"

# Validators
require "mini_tarball/validators/path_validator"
require "mini_tarball/validators/source_validator"

# Writers
require "mini_tarball/writers/content_writer"
require "mini_tarball/writers/null_writer"
require "mini_tarball/writers/placeholder_manager"
require "mini_tarball/writers/placeholder"
require "mini_tarball/writers/writer"
