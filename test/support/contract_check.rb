# frozen_string_literal: true

require "json"

# Lists every way one request strays from its Operation in the contract
# snapshot: a query parameter the Operation does not take, a filter or sort
# field it does not list, or a body field its schema does not declare, at
# any depth.
class ContractCheck
  PAGE_KEYS = %w[cursor limit].freeze

  def initialize(spec)
    @spec = spec
    @label = "#{spec.fetch("operation_id")} (#{spec.fetch("method")} #{spec.fetch("path")})"
  end

  # The violations of `request`, a WebMock::RequestSignature.
  def violations(request)
    @found = []
    check_query(request.uri.query_values || {})
    schema = @spec.dig("request_body", "content", "application/json", "schema")
    check_value(JSON.parse(request.body), [schema], "body") if schema && request.body && !request.body.empty?
    @found
  end

  private

  def check_query(values)
    documented = (@spec["parameters"] || []).select { _1["in"] == "query" }.to_h { [_1["name"], _1["description"]] }
    values.each do |name, value|
      next @found << "#{@label} takes no query parameter #{name.inspect}" unless documented.key?(name)

      check_fields(name, value, documented[name].to_s) unless PAGE_KEYS.include?(name)
    end
  end

  # The fields a filter or sort description lists in backticks.
  def check_fields(name, value, description)
    listed = description.scan(/`-?(\w+)`/).flatten
    return if listed.empty?

    fields = case name
             when "filter" then JSON.parse(value).map { _1["field"] }
             when "sort" then [value.delete_prefix("-")]
             else []
             end
    fields.reject { listed.include?(_1) }.each { @found << "#{@label} does not list #{_1.inspect} as a #{name} field" }
  end

  # Every Hash key must be a property one of `schemas` declares.
  def check_value(value, schemas, path)
    schemas = schemas.flat_map { flatten(_1) }
    case value
    when Hash then check_hash(value, schemas, path)
    when Array then value.each { check_value(_1, schemas.filter_map { |schema| schema["items"] }, "#{path}[]") }
    end
  end

  def check_hash(value, schemas, path)
    properties = schemas.filter_map { _1["properties"] }
    return if properties.empty? || schemas.any? { _1["additionalProperties"] }

    value.each do |key, nested|
      found = properties.filter_map { _1[key] }
      next @found << "#{@label} declares no field #{path}.#{key}" if found.empty?

      check_value(nested, found, "#{path}.#{key}")
    end
  end

  # A schema and every anyOf, oneOf and allOf branch in it.
  def flatten(schema)
    branches = (schema["anyOf"] || []) + (schema["oneOf"] || []) + (schema["allOf"] || [])
    [schema] + branches.flat_map { flatten(_1) }
  end
end
