# frozen_string_literal: true

module SuperDiff
  module OperationTrees
    class BinaryString < Core::AbstractOperationTree
      def self.applies_to?(value)
        value.is_a?(::String) && Differs::BinaryString.binary?(value)
      end

      protected

      def operation_tree_flattener_class
        OperationTreeFlatteners::BinaryString
      end
    end
  end
end
