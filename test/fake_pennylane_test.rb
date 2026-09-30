# frozen_string_literal: true

require "test_helper"
require "support/fake_pennylane"

class FakePennylaneTest < Minitest::Test
  BASE = "https://app.pennylane.com/api/external/v2"
  # A window boundary: 1_770_379_500 is a multiple of 5.
  START = 1_770_379_500.0

  def setup
    @time = VirtualClock.new(START)
    @fake = FakePennylane.new(clock: @time.clock, sleeper: @time.sleeper)
  end

  def get(path = "/me", token: "tok")
    @fake.call(request(:get, path, token:))
  end

  def request(verb, path, token: "tok", headers: {}, body: nil)
    headers = headers.merge("Authorization" => "Bearer #{token}") if token
    PennylaneClient::Request.new(verb:, url: "#{BASE}#{path}", headers:, body:)
  end

  # [status, ratelimit-limit, ratelimit-remaining, ratelimit-reset, retry-after]
  def summary(response)
    [response.status, *response.headers.values_at("ratelimit-limit", "ratelimit-remaining", "ratelimit-reset",
                                                  "retry-after")]
  end

  def test_answers_with_json_and_the_rate_limit_headers
    response = get

    assert_equal [200, "25", "24", "1770379505", nil], summary(response)
    assert_equal({ "id" => 1 }, JSON.parse(response.body))
  end

  def test_the_26th_request_in_a_window_is_a_429_with_retry_after
    25.times { assert_equal 200, get.status }
    @time.sleeper.call(3.2)
    response = get

    assert_equal [429, "25", "0", "1770379505", "2"], summary(response)
    assert_equal "Rate limit exceeded. Please retry in 2 seconds.", response.body
  end

  def test_the_window_resets_on_the_reported_second
    25.times { get }
    @time.sleeper.call(4.999)

    assert_equal 429, get.status
    @time.sleeper.call(0.001)

    assert_equal [200, "25", "24", "1770379510", nil], summary(get)
  end

  # Pennylane counts per token (guides/rate-limiting.md).
  def test_each_token_has_its_own_budget
    25.times { get(token: "a") }

    assert_equal 429, get(token: "a").status
    assert_equal 200, get(token: "b").status
  end

  def test_a_request_without_a_token_is_unauthorized
    response = @fake.call(request(:get, "/me", token: nil))

    assert_equal 401, response.status
    assert_nil response.headers["ratelimit-remaining"]
  end

  def test_counts_answers_by_verb_and_status
    26.times { get }
    @fake.call(request(:post, "/customer_invoices", token: "other", body: "{}"))

    assert_equal 25, @fake.count("GET 200")
    assert_equal 1, @fake.count("GET 429")
    assert_equal 1, @fake.count("POST 200")
    assert_equal 27, @fake.requests
  end

  # The client's limiter and the fake agree: sequential calls never see a 429.
  def test_a_client_never_hits_the_limit
    limiters = PennylaneClient::LimiterRegistry.new do
      PennylaneClient::Limiter.new(clock: @time.clock, sleeper: @time.sleeper)
    end
    client = PennylaneClient.new(token: "tok", transport: @fake, limiters:, logger: nil, on_request: nil)
    @time.sleeper.call(2.5) # start mid-window
    100.times { client.call(:getMe) }

    assert_equal 0, @fake.count("GET 429")
    assert_equal 100, @fake.count("GET 200")
  end
end
