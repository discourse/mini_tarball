# frozen_string_literal: true

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
