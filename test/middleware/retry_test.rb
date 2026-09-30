# frozen_string_literal: true

require "test_helper"

class RetryTest < Minitest::Test
  # rand always returns this, so full-jitter waits are exact.
  class FixedRandom
    def rand = 0.5
  end

  def setup
    @time = VirtualClock.new
    @events = []
  end

  def response(status, headers = {}) = PennylaneClient::Response.new(status:, headers:, body: "")

  def timeout = PennylaneClient::TimeoutError.new("Net::ReadTimeout")

  def run_retry(verb, *outcomes, retry_policy: :default)
    @transport = FakeTransport.new(*outcomes)
    middleware = PennylaneClient::Middleware::Retry.new(
      @transport, PennylaneClient::Instrumentation.new(on_request: @events.method(:<<)),
      sleeper: @time.sleeper, random: FixedRandom.new
    )
    middleware.call(PennylaneClient::Request.new(verb:, url: "https://app.pennylane.com/api/external/v2/journals",
                                                 headers: {}, body: nil, operation_id: :op, retry_policy:))
  end

  def attempts = @transport.requests.size

  # D5: a 5xx or a timeout may mean the write happened.
  def test_never_retries_post_put_or_delete_after_a_5xx
    %i[post put delete].each do |verb|
      assert_equal 503, run_retry(verb, response(503), response(200)).status
      assert_equal 1, attempts, verb
    end
  end

  def test_never_retries_post_put_or_delete_after_a_timeout_or_connection_error
    %i[post put delete].each do |verb|
      assert_raises(PennylaneClient::TimeoutError) { run_retry(verb, timeout, response(200)) }
      assert_equal 1, attempts, verb
      assert_raises(PennylaneClient::ConnectionError) { run_retry(verb, PennylaneClient::ConnectionError.new("x")) }
      assert_equal 1, attempts, verb
    end
  end

  # D5: a 429 means Pennylane did not run the request.
  def test_retries_post_put_and_delete_when_rate_limited
    %i[post put delete].each do |verb|
      assert_equal 201, run_retry(verb, response(429, "retry-after" => "2"), response(201)).status
      assert_equal 2, attempts, verb
    end
  end

  def test_sleeps_retry_after_when_rate_limited
    run_retry(:post, response(429, "retry-after" => "2"), response(201))

    assert_equal [2.0], @time.sleeps
  end

  def test_retries_get_after_a_5xx_or_no_response
    [response(500), response(502), response(503), response(504), timeout,
     PennylaneClient::ConnectionError.new("reset")].each do |outcome|
      assert_equal 200, run_retry(:get, outcome, response(200)).status
      assert_equal 2, attempts
    end
  end

  def test_does_not_retry_other_statuses
    [400, 401, 404, 409, 422, 501].each do |status|
      assert_equal status, run_retry(:get, response(status), response(200)).status
      assert_equal 1, attempts
    end
  end

  def test_stops_after_3_attempts
    assert_equal 503, run_retry(:get, response(503), response(503), response(503), response(200)).status
    assert_equal 3, attempts
  end

  def test_raises_the_last_error_when_attempts_run_out
    assert_raises(PennylaneClient::TimeoutError) { run_retry(:get, timeout, timeout, timeout) }
    assert_equal 3, attempts
  end

  # Full jitter: a random wait between 0 and 0.5 s, 1 s, ... per attempt.
  def test_backs_off_exponentially_with_full_jitter
    run_retry(:get, response(503), response(503), response(200))

    assert_equal [0.25, 0.5], @time.sleeps
  end

  def test_a_429_without_retry_after_backs_off
    run_retry(:post, response(429), response(201))

    assert_equal [0.25], @time.sleeps
  end

  def test_gives_up_when_retry_after_passes_the_30_second_cap
    assert_equal 429, run_retry(:get, response(429, "retry-after" => "20"), response(429, "retry-after" => "11"),
                                response(200)).status
    assert_equal [20.0], @time.sleeps
  end

  def test_retry_always_retries_a_post_after_a_5xx_or_timeout
    assert_equal 201, run_retry(:post, response(503), timeout, response(201), retry_policy: :always).status
    assert_equal 3, attempts
  end

  def test_emits_a_retry_event
    run_retry(:get, response(503), timeout, response(200))

    assert_equal [
      { type: :retry, operation_id: :op, method: "GET", path: "/api/external/v2/journals", attempt: 2, wait: 0.25,
        status: 503, error: nil },
      { type: :retry, operation_id: :op, method: "GET", path: "/api/external/v2/journals", attempt: 3, wait: 0.5,
        status: nil, error: "PennylaneClient::TimeoutError" }
    ], @events
  end
end
