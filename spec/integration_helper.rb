# frozen_string_literal: true

require_relative "spec_helper"
require "rspec/path_matchers"
require_relative "integration/support/gnu_tar"
require_relative "integration/support/bsd_tar"
require_relative "integration/support/tar_extractor"
require_relative "integration/support/hardlink_matcher"
require_relative "integration/support/mode_matcher"
require_relative "integration/support/archive_builder"

def extract_with_all(archive_path)
  Dir.mktmpdir do |tmpdir|
    TarExtractor.each_extractor(tmpdir:) do |ctx|
      raise "#{ctx.name} failed to extract #{archive_path}" unless ctx.extract(archive_path)
      yield ctx.extract_dir
    end
  end
end

RSpec.configure do |config|
  config.include RSpec::PathMatchers

  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:integration] = true
  end

  config.before(:suite) do
    unless GnuTar.available?
      if ENV["CI"]
        raise "GNU tar is required for integration tests in CI. #{GnuTar.skip_message}"
      else
        warn "WARNING: #{GnuTar.skip_message}"
      end
    end

    extractors =
      TarExtractor.extractors.map { |extractor| "#{extractor.name} (#{extractor.binary_path})" }
    puts "Integration extractors: #{extractors.join(", ")}"
  end

  config.before(:example, :integration) { skip GnuTar.skip_message unless GnuTar.available? }
end
