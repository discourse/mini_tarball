# frozen_string_literal: true

module SuperDiff
  module OperationTreeFlatteners
    class BinaryString < Core::AbstractOperationTreeFlattener
      CONTEXT_LINES = 3

      def build_tiered_lines
        lines =
          operation_tree.map do |operation|
            Core::Line.new(
              type: operation.name,
              indentation_level:,
              value:
                operation.value.inspect[1..-2]
                  .gsub('\\"', '"')
                  .gsub("\\'", "'")
                  .delete_suffix('\n'),
            )
          end

        filter_with_context(lines)
      end

      private

      def filter_with_context(lines)
        # Find indices of changed lines
        changed_indices = lines.each_with_index.filter_map { |line, idx| idx if line.type != :noop }

        return lines if changed_indices.empty?

        # Build set of indices to keep (changed lines + context)
        indices_to_keep = Set.new
        changed_indices.each do |idx|
          ((idx - CONTEXT_LINES)..(idx + CONTEXT_LINES)).each do |context_idx|
            indices_to_keep << context_idx if context_idx >= 0 && context_idx < lines.size
          end
        end

        # Build output with elision markers
        result = []
        prev_kept = -1

        lines.each_with_index do |line, idx|
          if indices_to_keep.include?(idx)
            # Add elision marker if there's a gap
            if prev_kept >= 0 && idx > prev_kept + 1
              result << Core::Line.new(
                type: :noop,
                indentation_level:,
                value: "# ... #{idx - prev_kept - 1} unchanged lines ...",
              )
            end
            result << line
            prev_kept = idx
          end
        end

        result
      end
    end
  end
end
