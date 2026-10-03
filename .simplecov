# frozen_string_literal: true

SimpleCov.configure do
  skip "/spec/"
  # mutant selects tests from this recording, see mutant.yml
  track_tests
end
