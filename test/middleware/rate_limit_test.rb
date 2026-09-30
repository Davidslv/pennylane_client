# frozen_string_literal: true

require "test_helper"
require "digest"

class RateLimitTest < Minitest::Test
  TOKEN = "pl-secret-token-7f3a9c"

  def setup
    @time = VirtualClock.new
    @events = []
    @keys = []
    @limiters = PennylaneClient::LimiterRegistry.new do |key|
      @keys << key
      PennylaneClient::Limiter.new(clock: @time.clock, sleeper: @time.sleeper)
    end
  end

  def rate_limit(transport)
    PennylaneClient::Middleware::RateLimit.new(transport, @limiters,
                                               PennylaneClient::Instrumentation.new(on_request: @events.method(:<<)))
  end

  def request(token = TOKEN)
    PennylaneClient::Request.new(verb: :get, url: "https://app.pennylane.com/api/external/v2/me?x=1",
                                 headers: { "Authorization" => "Bearer #{token}" }, body: nil, operation_id: :getMe)
  end

  def response(headers = {}) = PennylaneClient::Response.new(status: 200, headers:, body: "")

  def test_the_26th_call_waits_and_emits_a_wait_event
    middleware = rate_limit(->(_) { response })
    25.times { middleware.call(request) }

    assert_empty @events
    middleware.call(request)

    assert_equal [{ type: :wait, operation_id: :getMe, method: "GET", path: "/api/external/v2/me", wait: 5.0 }],
                 @events
  end

  def test_headers_from_a_response_drain_the_local_bucket
    reset = (@time.now + 3).to_i.to_s
    middleware = rate_limit(->(_) { response("ratelimit-remaining" => "0", "ratelimit-reset" => reset) })

    middleware.call(request)
    middleware.call(request)

    assert_equal [3.0], @time.sleeps
  end

  def test_ignores_missing_or_malformed_headers
    middleware = rate_limit(->(_) { response("ratelimit-remaining" => "soon", "ratelimit-reset" => "later") })

    3.times { middleware.call(request) }

    assert_empty @time.sleeps
  end

  def test_keys_limiters_by_the_sha256_of_the_token
    middleware = rate_limit(->(_) { response })
    middleware.call(request)
    middleware.call(request("other"))

    assert_equal [Digest::SHA256.hexdigest(TOKEN), Digest::SHA256.hexdigest("other")], @keys
  end
end

# 16 threads share one token against a server that enforces 25 per window
# and answers with its headers, as Pennylane does. A short window keeps the
# test fast.
class RateLimitThreadsTest < Minitest::Test
  PERIOD = 0.2

  # Fixed windows starting at the first request, 429 once a window is spent.
  class StrictServer
    attr_reader :statuses

    def initialize
      @lock = Mutex.new
      @statuses = []
    end

    def call(_request)
      @lock.synchronize do
        count
        @statuses << (@count > 25 ? 429 : 200)
        PennylaneClient::Response.new(status: @statuses.last, body: "", headers: {
                                        "ratelimit-remaining" => [25 - @count, 0].max.to_s,
                                        "ratelimit-reset" => @reset_at.to_s
                                      })
      end
    end

    private

    def count
      now = Time.now.to_f
      if @reset_at.nil? || now >= @reset_at
        @reset_at = now + PERIOD
        @count = 0
      end
      @count += 1
    end
  end

  def test_16_threads_see_no_rejections_and_no_deadlock
    server = StrictServer.new
    limiters = PennylaneClient::LimiterRegistry.new { PennylaneClient::Limiter.new(period: PERIOD) }
    middleware = PennylaneClient::Middleware::RateLimit.new(server, limiters, PennylaneClient::Instrumentation.new)
    request = PennylaneClient::Request.new(verb: :get, url: "https://app.pennylane.com/api/external/v2/me",
                                           headers: { "Authorization" => "Bearer tok" }, body: nil)

    threads = Array.new(16) { Thread.new { 5.times { middleware.call(request) } } }

    assert(threads.all? { _1.join(10) }, "a thread did not finish: deadlock")
    assert_equal [200] * 80, server.statuses
  end
end
