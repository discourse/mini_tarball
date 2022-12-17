# frozen_string_literal: true

require "simplecov" if ENV["COVERAGE"]
require "mini_tarball"
require "super_diff/rspec"
require_relative "helper/super_diff/extension"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

def fixture_path(relative_path)
  File.expand_path(File.join("fixtures", relative_path), __dir__)
end

def fixture(relative_path)
  File.binread(fixture_path(relative_path))
end
