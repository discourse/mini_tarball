# frozen_string_literal: true

require_relative "spec_helper"
require "rspec/path_matchers"
require_relative "integration/support/gnu_tar"
require_relative "integration/support/hardlink_matcher"
require_relative "integration/support/archive_builder"

RSpec.configure do |config|
  config.include RSpec::PathMatchers

  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:integration] = true
  end

  config.before(:suite) do
    next if GnuTar.available?

    if ENV["CI"]
      raise "GNU tar is required for integration tests in CI. #{GnuTar.skip_message}"
    else
      warn "WARNING: #{GnuTar.skip_message}"
    end
  end

  config.before(:example, :integration) { skip GnuTar.skip_message unless GnuTar.available? }
end
