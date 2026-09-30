# frozen_string_literal: true

require "digest"
require "json"
require "uri"

# A stand-in for Pennylane that never touches the network, for tests and for
# the load and stress runs (AGENTS.md: never load-test Pennylane).
#
# It is a Transport (`call(request) -> Response`), so a Client can use it in
# process, and FakePennylane::Server puts the same fake on a local socket.
#
# It enforces Pennylane's rate limit as guides/rate-limiting.md describes
# it: `limit` requests per `period` seconds per token, with
# `ratelimit-limit`, `ratelimit-remaining` and `ratelimit-reset` (a Unix
# time in whole seconds) on every answer, and `retry-after` on a 429. The
# windows are fixed and start on multiples of `period` since the epoch, so
# with the default 5 s every reset is a whole second, as Pennylane reports
# it. How Pennylane places its windows is not documented; this is the
# simplest reading that fits the headers.
#
# Every answer is counted by verb and status (`count("GET 429")`).
class FakePennylane
  # What the fake does with one request: answer with `response` after
  # `delay` seconds, or, when `drop` is :reset or :hang, answer nothing.
  Reply = Data.define(:response, :delay, :drop) do
    def initialize(response: nil, delay: 0, drop: nil) = super
  end

  JSON_HEADERS = { "content-type" => "application/json; charset=utf-8" }.freeze

  def initialize(limit: 25, period: 5, clock: -> { Time.now.to_f }, sleeper: ->(seconds) { sleep(seconds) })
    @limit = limit
    @period = period
    @clock = clock
    @sleeper = sleeper
    @lock = Mutex.new
    @windows = {}
    @counts = Hash.new(0)
  end

  # The Transport interface, for a Client in the same process.
  def call(request)
    reply = handle(request)
    @sleeper.call(reply.delay) if reply.delay.positive?
    reply.response
  end

  # Decides the Reply for a request and counts it. FakePennylane::Server
  # calls this and does the waiting and hanging up itself.
  def handle(request)
    reply = answer(request)
    outcome = reply.drop || reply.response.status
    @lock.synchronize { @counts["#{request.verb.to_s.upcase} #{outcome}"] += 1 }
    reply
  end

  def count(key) = @lock.synchronize { @counts[key] }

  def requests = @lock.synchronize { @counts.values.sum }

  def inspect = "#<#{self.class.name} limit=#{@limit} period=#{@period}>"

  private

  def answer(request)
    token = bearer(request)
    return Reply.new(response: error(401, "unauthorized", "Missing or invalid token")) unless token

    allowed, headers = admit(token)
    return Reply.new(response: rate_limited(headers)) unless allowed

    Reply.new(response: json(200, { id: 1 }, headers))
  end

  def bearer(request)
    value = header(request, "authorization").to_s
    value.delete_prefix("Bearer ") if value.start_with?("Bearer ") && value.length > 7
  end

  def header(request, name)
    request.headers.find { |key, _| key.casecmp?(name) }&.last
  end

  # Takes one request from the token's window. Returns whether it was
  # allowed and the rate-limit headers to send back.
  def admit(token)
    now = @clock.call
    window = (now / @period).floor
    used = @lock.synchronize { take(Digest::SHA256.hexdigest(token), window) }
    reset = ((window + 1) * @period).ceil
    headers = rate_headers(@limit - used, reset)
    return [true, headers] if used <= @limit

    [false, headers.merge("retry-after" => [(reset - now).ceil, 1].max.to_s)]
  end

  def rate_headers(remaining, reset)
    { "ratelimit-limit" => @limit.to_s, "ratelimit-remaining" => [remaining, 0].max.to_s,
      "ratelimit-reset" => reset.to_s }
  end

  # Returns the count in the window including this request; a request over
  # the limit is refused and not counted.
  def take(key, window)
    seen, used = @windows[key]
    used = 0 unless seen == window
    @windows[key] = [window, [used + 1, @limit].min]
    used + 1
  end

  def rate_limited(headers)
    body = "Rate limit exceeded. Please retry in #{headers.fetch("retry-after")} seconds."
    PennylaneClient::Response.new(status: 429, headers: headers.merge("content-type" => "text/plain"), body:)
  end

  def json(status, body, headers = {})
    PennylaneClient::Response.new(status:, headers: JSON_HEADERS.merge(headers), body: JSON.generate(body))
  end

  def error(status, code, message, headers = {}) = json(status, { error: code, message: }, headers)
end
