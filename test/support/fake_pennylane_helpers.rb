# frozen_string_literal: true

require "support/fake_pennylane"

# A FakePennylane on a VirtualClock, and a Client on the same clock.
module FakePennylaneHelpers
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

  def client
    @client ||= PennylaneClient.new(token: "tok", transport: @fake, logger: nil, on_request: nil,
                                    limiters: PennylaneClient::LimiterRegistry.new do
                                      PennylaneClient::Limiter.new(clock: @time.clock, sleeper: @time.sleeper)
                                    end)
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
end
