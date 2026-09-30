# How-to recipes

Task-oriented recipes. Each is added when the feature it describes ships.

## Convert money and dates

Pennylane sends amounts as decimal strings and dates as ISO 8601 strings. The gem returns them unchanged:

```ruby
require "bigdecimal"
require "date"

BigDecimal(invoice[:amount])
Date.iso8601(invoice[:date])
```

On Ruby 3.4 and newer `bigdecimal` is a bundled gem, so add `gem "bigdecimal"` to your own Gemfile. The client itself never requires it.

Send amounts as strings too. Pennylane rejects numeric amounts with a 400. The client converts a `BigDecimal`, `Date` or `Time` you pass for you:

```ruby
client.call(:createTransaction, bank_account_id: 1, label: "Rent",
                                amount: BigDecimal("12.50"), date: Date.today)   # sends "12.5" and "2026-09-30"
```

## Log requests and collect metrics

```ruby
PennylaneClient.configure do |config|
  config.logger = Rails.logger
  config.on_request = ->(event) { StatsD.measure("pennylane.request", event[:duration]) }
end
```

Configure before building clients; a client reads the configuration when it is built. `PennylaneClient.new(token:, logger:, on_request:)` overrides it per client.

Each attempt sent to Pennylane, each retry and each rate-limit wait writes one line and fires one event, a frozen Hash. `type` says which:

```ruby
{ type: :request, operation_id: :getMe, method: "GET", path: "/api/external/v2/me", status: 200, error: nil, duration: 84.2 }
{ type: :retry, operation_id: :getMe, method: "GET", path: "/api/external/v2/me", attempt: 2, wait: 0.3, status: 503, error: nil }
{ type: :wait, operation_id: :getMe, method: "GET", path: "/api/external/v2/me", wait: 0.8 }
```

For a request, `status` is `nil` and `error` names the error class when no response arrived, and `duration` is milliseconds on the wire. A retry names the attempt about to be sent and what the last one got. `wait` is in seconds. The token is never in any of them.

## Retries and the rate limit

Pennylane allows 25 requests per 5 seconds per token. The client keeps one bucket per token for the whole process, shared by every client and thread, and corrects it from the `ratelimit-remaining` and `ratelimit-reset` headers on every response. When the bucket is empty, a call waits for the window to reset.

Retries follow one rule: never send a write twice unless Pennylane said it did not run it.

| Answer | GET | POST, PUT, DELETE |
|---|---|---|
| 429 | retried after `retry-after` | retried after `retry-after` |
| 500, 502, 503, 504 | retried | raised |
| `ConnectionError`, `TimeoutError` | retried | raised |
| anything else | raised | raised |

A call makes at most 3 attempts, with a random backoff (up to 0.5 s, then 1 s), and waits at most 30 s in total. A `retry-after` that would pass the 30 s raises `RateLimitError` at once, with `#retry_after` set. Change the cap per client:

```ruby
PennylaneClient.new(token:, max_retry_wait: 10)
```

When you know a write is safe to repeat, opt in per call. `retry` is not sent to Pennylane:

```ruby
client.call(:putCategoryGroup, id: 7, label: "Sales", retry: :always)
```

### Share the budget across processes

The bucket is per process. Several processes on one token each think they have 25 requests; the headers and 429 retries absorb the overlap. To share one budget, give the client a registry that builds your own limiter. A limiter responds to `acquire` (wait for a call, return the seconds waited) and `update(remaining:, reset_at:)` (`reset_at` is a Unix time or `nil`). The key is a SHA-256 of the token:

```ruby
limiters = PennylaneClient::LimiterRegistry.new { |key| MyRedisLimiter.new("pennylane:#{key}") }
client = PennylaneClient.new(token:, limiters:)
```

## Handle a validation error

```ruby
begin
  client.call(:postJournals, code: "HA")
rescue PennylaneClient::ValidationError => e
  e.message   # "422 unprocessable_entity: ..."
  e.details   # { field: "label", issue: "is required" }, when Pennylane sends it
end
```
