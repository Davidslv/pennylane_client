# frozen_string_literal: true

# Builds a value from a contract snapshot schema, out of the snapshot's own
# `example`, `default` and `enum` values, so a stubbed answer has the shape
# Pennylane documents and no field invented for a test.
module ContractExamples
  DATES = { "date" => "2026-09-30", "date-time" => "2026-09-30T10:00:00.000000Z" }.freeze
  TYPES = { "integer" => 1, "number" => 1, "boolean" => true }.freeze

  module_function

  def example(schema)
    return nil if schema.nil?
    return schema["example"] if schema.key?("example")

    branches = schema["anyOf"] || schema["oneOf"]
    return example(branches.first) if branches
    return merged(schema["allOf"]) if schema["allOf"]

    typed(schema)
  end

  def merged(parts)
    parts.map { example(_1) }.reduce({}) { |all, part| all.merge(part.is_a?(Hash) ? part : {}) }
  end

  def typed(schema)
    case schema["type"]
    when "object" then (schema["properties"] || {}).transform_values { example(_1) }
    when "array" then [example(schema["items"])]
    else scalar(schema)
    end
  end

  def scalar(schema)
    return schema["default"] if schema.key?("default")
    return schema["enum"].first if schema["enum"]
    return nil if schema["nullable"]

    TYPES.fetch(schema["type"]) { DATES.fetch(schema["format"], "") }
  end
end
