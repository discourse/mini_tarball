# frozen_string_literal: true

require_relative "patches/differ"
require_relative "differs/binary_string"
require_relative "inspection_tree_builders/binary_string"
require_relative "operation_tree_flatteners/binary_string"
require_relative "operation_trees/binary_string"
require_relative "operation_tree_builders/binary_string"

SuperDiff.configure do |config|
  config.prepend_extra_differ_class(SuperDiff::Differs::BinaryString)
  config.prepend_extra_operation_tree_builder_class(SuperDiff::OperationTreeBuilders::BinaryString)
  config.prepend_extra_inspection_tree_builder_class(
    SuperDiff::InspectionTreeBuilders::BinaryString,
  )
end
