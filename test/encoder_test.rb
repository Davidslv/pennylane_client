# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "date"
require "time"

class EncoderTest < Minitest::Test
  def encode(value) = PennylaneClient::Encoder.encode(value)

  def test_sends_a_big_decimal_as_a_plain_decimal_string
    assert_equal "230.32", encode(BigDecimal("230.32"))
    assert_equal "0.1", encode(BigDecimal("0.1"))
  end

  def test_sends_a_date_in_iso_format
    assert_equal "2026-01-31", encode(Date.new(2026, 1, 31))
  end

  def test_sends_a_time_in_iso_format
    assert_equal "2026-01-31T09:05:00Z", encode(Time.utc(2026, 1, 31, 9, 5))
    assert_equal "2026-01-31T09:05:00+01:00", encode(Time.new(2026, 1, 31, 9, 5, 0, "+01:00"))
  end

  def test_encodes_values_nested_in_hashes_and_arrays
    payload = { amount: BigDecimal("12.5"), lines: [{ date: Date.new(2026, 2, 1), label: "Rent" }] }

    assert_equal({ amount: "12.5", lines: [{ date: "2026-02-01", label: "Rent" }] }, encode(payload))
  end

  def test_leaves_everything_else_untouched
    [1, 1.5, "230.32", true, false, :draft].each { assert_equal _1, encode(_1) }
    assert_nil encode(nil)
  end
end
