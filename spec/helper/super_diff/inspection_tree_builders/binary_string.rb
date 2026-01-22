# frozen_string_literal: true

module SuperDiff
  module InspectionTreeBuilders
    class BinaryString < Core::AbstractInspectionTreeBuilder
      def self.applies_to?(value)
        value.is_a?(::String) && Differs::BinaryString.binary?(value)
      end

      def call
        Core::InspectionTree.new do |t1|
          t1.as_lines_when_rendering_to_lines do |t2|
            t2.add_text "<binary string (#{object.bytesize} bytes)>"
          end
        end
      end
    end
  end
end
