# frozen_string_literal: true

require "test_helper"
require "support/fake_pennylane_helpers"

# FakePennylane#inject, the misbehaviour rake stress runs on.
class FakePennylaneFaultsTest < Minitest::Test
  include FakePennylaneHelpers

  def test_a_server_error_lasts_as_many_requests_as_asked
    @fake.inject(:server_error, times: 2, status: 502)

    assert_equal [502, 502, 200], Array.new(3) { get.status }
    assert_equal "25", get.headers["ratelimit-limit"]
  end

  def test_a_fault_lasts_until_healed
    @fake.inject(:server_error)

    assert_equal [503, 503], Array.new(2) { get.status }
    @fake.heal

    assert_equal 200, get.status
  end

  def test_a_rate_limit_storm_refuses_whatever_the_budget_says
    @fake.inject(:rate_limited, times: 1, retry_after: 3)

    assert_equal [429, "25", "0", "1770379503", "3"], summary(get)
    assert_equal "24", get.headers["ratelimit-remaining"], "a refused request is not counted"
  end

  def test_a_slow_answer_arrives_after_the_delay
    @fake.inject(:slow, delay: 0.5)

    assert_equal 200, get.status
    assert_equal [0.5], @time.sleeps
  end

  def test_a_hang_is_a_timeout_and_a_reset_is_a_connection_error
    @fake.inject(:hang, times: 1, delay: 2)

    assert_raises(PennylaneClient::TimeoutError) { get }
    @fake.inject(:reset, times: 1)

    assert_raises(PennylaneClient::ConnectionError) { get }
    assert_equal [1, 1, [2]], [@fake.count("GET hang"), @fake.count("GET reset"), @time.sleeps]
  end

  def test_malformed_json_fails_the_client_with_the_base_error
    @fake.inject(:malformed)

    error = assert_raises(PennylaneClient::Error) { client.call(:getMe) }

    assert_instance_of PennylaneClient::Error, error
    assert_equal "200: the response body is not JSON", error.message
  end

  def test_refuses_an_unknown_fault
    assert_raises(ArgumentError) { @fake.inject(:gremlins) }
  end
end
