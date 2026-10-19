# frozen_string_literal: true

module Corobook
  module ChordPro
    # A thin wrapper over the versioned JSONB hash (design §4.2). Carries no behaviour beyond
    # access; transforms live in Corobook::ChordPro::Transform so the stored shape stays plain.
    class ParsedLyric
      VERSION = 1

      attr_reader :data

      def self.from_hash(hash)
        new(hash)
      end

      def initialize(data)
        @data = data
      end

      def version = @data["version"]
      def meta = @data["meta"]
      def sections = @data["sections"]

      def to_h = @data

      def ==(other) = other.is_a?(ParsedLyric) && other.data == @data
    end
  end
end
