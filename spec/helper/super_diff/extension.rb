# frozen_string_literal: true

require_relative "patches/differ"
require_relative "operation_tree_builders/binary_string"
require_relative "differs/binary_string"

SuperDiff.configure do |config|
  config.add_extra_differ_class(SuperDiff::Differs::BinaryString)
  config.add_extra_operation_tree_builder_class(SuperDiff::OperationTreeBuilders::BinaryString)
end
