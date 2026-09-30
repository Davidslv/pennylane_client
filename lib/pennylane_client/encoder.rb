# frozen_string_literal: true

require "time" # Time#xmlschema is only in core from Ruby 3.4

module PennylaneClient
  # Converts request values Pennylane would otherwise receive in the wrong form.
  #
  # - BigDecimal becomes a plain decimal String ("230.32"). Plain `to_json`
  #   would send "0.23032e3", and Pennylane wants amounts as strings.
  # - Date, Time and DateTime become ISO 8601 Strings.
  # - Hashes and Arrays are walked. Everything else passes through untouched.
  #
  # Nothing here is required: `bigdecimal` is a bundled gem, so the encoder
  # only handles the classes the caller has already loaded (proposal 0001, D6).
  module Encoder
    module_function

    def encode(value)
      case value
      when Hash then value.transform_values { encode(_1) }
      when Array then value.map { encode(_1) }
      else scalar(value)
      end
    end

    def scalar(value)
      if defined?(::BigDecimal) && value.is_a?(::BigDecimal)
        value.to_s("F")
      elsif defined?(::Date) && value.is_a?(::Date)
        value.iso8601
      elsif value.is_a?(::Time)
        value.xmlschema
      else
        value
      end
    end
  end
end
