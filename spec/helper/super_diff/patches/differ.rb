# frozen_string_literal: true

# Without this patch, binary strings without newlines would be considered
# "singleline strings" and SuperDiff would skip showing a diff entirely.
# This ensures binary strings always get a hex diff.

module SuperDiff
  module DifferMonkeyPatch
    def comparing_singleline_strings?
      super && !Differs::BinaryString.binary?(expected) && !Differs::BinaryString.binary?(actual)
    end
  end

  module RSpec
    class Differ
      prepend DifferMonkeyPatch
    end
  end
end
