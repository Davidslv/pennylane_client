# frozen_string_literal: true

require "time" # Time#xmlschema is only in core from Ruby 3.4

module PennylaneClient
  # Converts request values Pennylane would otherwise receive in the wrong form.
  #
  # - BigDecimal becomes a plain decimal String ("230.32"). Plain `to_json`
  #   would send "0.23032e3", and Pennylane wants amounts as strings.
  # - Date, Time and DateTime become ISO 8601 Strings. A Time or DateTime
  #   with a fraction of a second keeps it to the microsecond
  #   ("2025-06-25T11:54:18.589480Z"), so a changelog resumed from a parsed
  #   processed_at starts where it stopped. A whole second is sent without
  #   a fraction. RFC 3339 allows the fraction wherever it allows a time.
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

    # Pennylane's timestamps (processed_at, start_date) carry microseconds.
    FRACTION_DIGITS = 6

    def scalar(value)
      if defined?(::BigDecimal) && value.is_a?(::BigDecimal)
        value.to_s("F")
      elsif value.is_a?(::Time) || (defined?(::Date) && value.is_a?(::Date))
        timestamp(value)
      else
        value
      end
    end

    # A Date, or a Time or DateTime with its fraction of a second, if any.
    def timestamp(value)
      case value
      when ::Time then value.xmlschema(fraction_digits(value.subsec))
      when ::DateTime then value.iso8601(fraction_digits(value.sec_fraction))
      else value.iso8601
      end
    end

    def fraction_digits(fraction) = fraction.zero? ? 0 : FRACTION_DIGITS
  end
end
