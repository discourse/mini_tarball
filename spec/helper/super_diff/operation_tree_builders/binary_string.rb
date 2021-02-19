# frozen_string_literal: true

module SuperDiff
  module OperationTreeBuilders
    class BinaryString < MultilineString
      def self.applies_to?(expected, actual)
        SuperDiff::Differs::BinaryString.applies_to?(expected, actual)
      end

      def initialize(*args)
        args.first[:expected] = pretty_hex(args.first[:expected])
        args.first[:actual] = pretty_hex(args.first[:actual])

        super(*args)
      end

      private

      def split_into_lines(str)
        super.map { |line| line.delete_suffix("\\n") }
      end

      def pretty_hex(binary)
        binary.unpack("C*").each_slice(16).each_with_index.map do |group, index|
          index = "%08x" % (index * 16)
          text = group.map { |c| to_char(c) }.join("")
          hex = group
            .map { |c| "%02x" % c }
            .each_slice(2).map { |octets| octets.join("") }
            .join(" ")

          "#{index}: #{hex}  #{text}"
        end.join("\n")
      end

      def to_char(c)
        (32..126).include?(c) ? c.chr : "."
      end
    end
  end
end
