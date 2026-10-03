# frozen_string_literal: true

RSpec::Matchers.define :be_hardlink_of do |expected_path|
  match do |actual_path|
    File.exist?(actual_path) && File.exist?(expected_path) &&
      File.stat(actual_path).ino == File.stat(expected_path).ino
  end

  failure_message { |actual_path| "expected #{actual_path} to be a hardlink of #{expected_path}" }
end
