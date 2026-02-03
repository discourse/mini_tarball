# frozen_string_literal: true

RSpec::Matchers.define :have_mode do |expected_mode|
  match do |path|
    @actual_mode = File.stat(path).mode & 0o777
    @actual_mode == expected_mode
  end

  failure_message do |path|
    "expected #{path} to have mode #{format("%04o", expected_mode)}, " \
      "but was #{format("%04o", @actual_mode)}"
  end
end
