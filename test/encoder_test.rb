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

  # Pennylane's processed_at and start_date carry microseconds. Dropping
  # them would move a changelog resume up to a second earlier.
  def test_keeps_the_microseconds_of_a_time
    assert_equal "2025-06-25T11:54:18.589480Z", encode(Time.parse("2025-06-25T11:54:18.589480Z"))
    assert_equal "2025-06-25T11:54:18.589480+02:00", encode(Time.parse("2025-06-25T11:54:18.589480+02:00"))
  end

  # Microseconds are Pennylane's precision. Truncating never moves a time later.
  def test_truncates_below_microseconds
    assert_equal "2025-06-25T11:54:18.589480Z", encode(Time.at(1_750_852_458, 589_480_999, :nsec).utc)
  end

  def test_keeps_the_microseconds_of_a_date_time
    assert_equal "2025-06-25T11:54:18.589480+00:00", encode(DateTime.parse("2025-06-25T11:54:18.589480Z"))
    assert_equal "2025-06-25T11:54:18+00:00", encode(DateTime.new(2025, 6, 25, 11, 54, 18))
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
