# frozen_string_literal: true

module Corobook
  module ChordPro
    # The round-trip gate (design §4.3a, Req 11.2). Lyric/chord content must survive verbatim;
    # directive lines may be canonicalized, so the gate compares the RE-PARSED structure rather
    # than raw bytes: parse(source) must equal parse(serialize(parse(source))). A parser that
    # loses a chord, a space inside text, or a segment fails this.
    module RoundTrip
      module_function

      def stable?(source)
        once = Parser.parse(source)
        twice = Parser.parse(Serializer.serialize(once))
        once == twice
      end

      def diff(source)
        once = Parser.parse(source).to_h
        twice = Parser.parse(Serializer.serialize(Parser.parse(source))).to_h
        { once: once, twice: twice }
      end
    end
  end
end
