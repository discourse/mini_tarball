# frozen_string_literal: true

module SuperDiff
  module Differs
    class BinaryString < Base
      def self.applies_to?(expected, actual)
        expected.is_a?(::String) && actual.is_a?(::String) &&
          (binary?(expected) || binary?(actual))
      end

      def self.binary?(string)
        string.encoding == Encoding::ASCII_8BIT
      end

      private

      def operation_tree_builder_class
        OperationTreeBuilders::BinaryString
      end
    end
  end
end
