# frozen_string_literal: true

module Corobook
  # Recursive deep copy for the plain JSON-shaped parsed data (hashes, arrays, strings, numbers,
  # booleans, nil). Used instead of Marshal round-tripping: the input is our own structure, never
  # untrusted serialized bytes, so this is both safe and avoids Brakeman's Marshal.load warning.
  module DeepDup
    module_function

    def call(obj)
      case obj
      when Hash  then obj.each_with_object({}) { |(k, v), h| h[k] = call(v) }
      when Array then obj.map { |v| call(v) }
      when String then obj.dup
      else obj
      end
    end
  end
end
