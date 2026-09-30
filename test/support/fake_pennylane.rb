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
# - Rate limit: Pennylane's, per token (FakePennylane::RateLimit).
# - `collection(path, size:)`: a GET on `path` answers with cursor pages of
#   generated items (FakePennylane::Collection).
# - A request with a body is read to the end and answered with
#   `{"id": 1, "received": <bytes>}`, so an upload can be checked.
# - Anything else is `{"id": 1}`.
#
# Every answer is counted by verb and status (`count("GET 429")`).
class FakePennylane
  # What the fake does with one request: answer with `response` after
  # `delay` seconds, or, when `drop` is :reset or :hang, answer nothing.
  Reply = Data.define(:response, :delay, :drop) do
    def initialize(response: nil, delay: 0, drop: nil) = super
  end

  JSON_HEADERS = { "content-type" => "application/json; charset=utf-8" }.freeze
  CHUNK = 64 * 1024

  def initialize(limit: 25, period: 5, clock: -> { Time.now.to_f }, sleeper: ->(seconds) { sleep(seconds) })
    @rate_limit = RateLimit.new(limit:, period:, clock:)
    @sleeper = sleeper
    @lock = Mutex.new
    @faults = Faults.new
    @collections = {}
    @counts = Hash.new(0)
  end

  def collection(path, size:)
    @lock.synchronize { @collections[path] = Collection.new(size) }
    self
  end

  # Misbehaves on the next `times` requests, or until `heal`:
  #
  # - :rate_limited, a 429 storm: every request is refused with
  #   `retry-after`, whatever the token's budget;
  # - :server_error, a 5xx with `status`;
  # - :slow, the normal answer after `delay` seconds;
  # - :hang, no answer: the connection stays silent for `delay` seconds,
  #   then closes (in process: TimeoutError after `delay`);
  # - :reset, the connection is reset (in process: ConnectionError);
  # - :malformed, a 200 whose JSON body is cut short.
  #
  # Every kind but :rate_limited takes a call from the budget first, as the
  # request reached Pennylane.
  def inject(kind, times: nil, status: 503, delay: 1.0, retry_after: 1)
    @faults.inject(Faults::Fault.new(kind:, status:, delay:, retry_after:), times)
    self
  end

  def heal
    @faults.heal
    self
  end

  # The Transport interface, for a Client in the same process.
  def call(request)
    reply = handle(request)
    @sleeper.call(reply.delay) if reply.delay.positive?
    case reply.drop
    when :hang then raise PennylaneClient::TimeoutError, "FakePennylane did not answer"
    when :reset then raise PennylaneClient::ConnectionError, "FakePennylane reset the connection"
    end
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

  def inspect = "#<#{self.class.name} #{@rate_limit.inspect}>"

  def self.json(status, body, headers = {})
    PennylaneClient::Response.new(status:, headers: JSON_HEADERS.merge(headers), body: JSON.generate(body))
  end

  def self.error(status, code, message, headers = {}) = json(status, { error: code, message: }, headers)

  private

  def answer(request)
    token = bearer(request)
    return Reply.new(response: self.class.error(401, "unauthorized", "Missing or invalid token")) unless token

    fault = @faults.take
    return storm(fault) if fault&.kind == :rate_limited

    allowed, headers = @rate_limit.admit(token)
    return Reply.new(response: RateLimit.refusal(headers)) unless allowed

    fault ? misbehave(fault, request, headers) : Reply.new(response: route(request, headers))
  end

  def storm(fault) = Reply.new(response: RateLimit.refusal(@rate_limit.storm(fault.retry_after)))

  def misbehave(fault, request, headers)
    case fault.kind
    when :server_error
      Reply.new(response: self.class.error(fault.status, "internal_error", "FakePennylane failed on purpose", headers))
    when :slow then Reply.new(response: route(request, headers), delay: fault.delay)
    when :hang then Reply.new(delay: fault.delay, drop: :hang)
    when :reset then Reply.new(drop: :reset)
    when :malformed
      Reply.new(response: PennylaneClient::Response.new(status: 200, headers: JSON_HEADERS.merge(headers),
                                                        body: '{"items": ['))
    end
  end

  def bearer(request)
    value = request.headers.find { |name, _| name.casecmp?("authorization") }&.last.to_s
    value.delete_prefix("Bearer ") if value.start_with?("Bearer ") && value.length > 7
  end

  def route(request, headers)
    uri = URI(request.url)
    collection = @lock.synchronize { @collections[uri.path] } if request.verb == :get
    return collection.page(uri.query, headers) if collection
    return self.class.json(200, { id: 1 }, headers) if request.body.nil?

    self.class.json(200, { id: 1, received: read_all(request.body) }, headers)
  end

  # A Transport rewinds a streamed body before sending it.
  def read_all(body)
    return body.to_s.bytesize unless body.respond_to?(:read)

    body.rewind if body.respond_to?(:rewind)
    buffer = String.new
    size = 0
    size += buffer.bytesize while body.read(CHUNK, buffer)
    size
  end

  # Pennylane's rate limit as guides/rate-limiting.md describes it: `limit`
  # requests per `period` seconds per token, with `ratelimit-limit`,
  # `ratelimit-remaining` and `ratelimit-reset` (a Unix time in whole
  # seconds) on every answer, and `retry-after` on a 429.
  #
  # Windows are fixed and start on multiples of `period` since the epoch, so
  # with the default 5 s every reset is a whole second, as Pennylane reports
  # it. How Pennylane places its windows is not documented; this is the
  # simplest reading that fits the headers. A refused request is not
  # counted. Tokens are kept as SHA-256 digests.
  class RateLimit
    def initialize(limit:, period:, clock:)
      @limit = limit
      @period = period
      @clock = clock
      @lock = Mutex.new
      @windows = {}
    end

    # Takes one request from the token's window. Returns whether it was
    # allowed and the headers to answer with.
    def admit(token)
      now = @clock.call
      window = (now / @period).floor
      used = @lock.synchronize { take(Digest::SHA256.hexdigest(token), window) }
      reset = ((window + 1) * @period).ceil
      headers = headers(used, reset)
      return [true, headers] if used <= @limit

      [false, headers.merge("retry-after" => [(reset - now).ceil, 1].max.to_s)]
    end

    # The headers of a 429 storm: nothing left until `retry_after` has passed.
    def storm(retry_after)
      reset = (@clock.call + retry_after).ceil
      { "ratelimit-limit" => @limit.to_s, "ratelimit-remaining" => "0", "ratelimit-reset" => reset.to_s,
        "retry-after" => retry_after.to_s }
    end

    def headers(used, reset)
      { "ratelimit-limit" => @limit.to_s, "ratelimit-remaining" => [@limit - used, 0].max.to_s,
        "ratelimit-reset" => reset.to_s }
    end

    def self.refusal(headers)
      body = "Rate limit exceeded. Please retry in #{headers.fetch("retry-after")} seconds."
      PennylaneClient::Response.new(status: 429, headers: headers.merge("content-type" => "text/plain"), body:)
    end

    def inspect = "limit=#{@limit} period=#{@period}"

    private

    # The count in the window including this request.
    def take(key, window)
      seen, used = @windows[key]
      used = 0 unless seen == window
      @windows[key] = [window, [used + 1, @limit].min]
      used + 1
    end
  end

  # The fault in force and how many more requests it lasts (nil: until
  # healed). Thread-safe.
  class Faults
    KINDS = %i[rate_limited server_error slow hang reset malformed].freeze
    Fault = Data.define(:kind, :status, :delay, :retry_after)

    def initialize
      @lock = Mutex.new
      @fault = nil
      @left = nil
    end

    def inject(fault, times)
      raise ArgumentError, "unknown fault #{fault.kind.inspect}, not one of #{KINDS}" unless KINDS.include?(fault.kind)

      @lock.synchronize do
        @fault = fault
        @left = times
      end
    end

    def heal = @lock.synchronize { @fault = nil }

    # The fault for this request, or nil.
    def take
      @lock.synchronize do
        fault = @fault
        @left -= 1 if fault && @left
        @fault = nil if @left&.zero?
        fault
      end
    end
  end

  # `size` generated items served in cursor pages
  # (guides/cursor-pagination.md). Items are built per page, so a
  # collection of 100k costs nothing until it is read.
  class Collection
    # Pennylane's default page size.
    DEFAULT_LIMIT = 20
    CURSOR = /\Ac([0-9a-z]+)\z/

    def initialize(size)
      @size = size
    end

    def page(query, headers)
      params = URI.decode_www_form(query.to_s).to_h
      offset = params.key?("cursor") ? CURSOR.match(params["cursor"])&.[](1)&.to_i(36) : 0
      return FakePennylane.error(400, "invalid_cursor", "Unknown cursor", headers) unless offset

      last = [offset + Integer(params.fetch("limit", DEFAULT_LIMIT)), @size].min
      FakePennylane.json(200, body(offset, last), headers)
    end

    private

    def body(offset, last)
      more = last < @size
      { items: (offset...last).map { { id: _1 + 1, label: "Item #{_1 + 1}", amount: "10.00" } },
        has_more: more, next_cursor: more ? "c#{last.to_s(36)}" : nil }
    end
  end
end
