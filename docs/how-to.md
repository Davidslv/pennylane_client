# How-to recipes

Task recipes. In each example `client` is a client built as in [getting started](getting-started.md):

<!-- not run: the test suite builds this client -->
```ruby
client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))
```

Every example below runs in the test suite against the answers Pennylane documents, so a recipe that no longer matches the gem fails the build.

**The client:** [walk a list](#walk-a-list), [filter and sort a list](#filter-and-sort-a-list), [retry a request](#retry-a-request), [stay inside the rate limit](#stay-inside-the-rate-limit), [set timeouts](#set-timeouts), [upload a file](#upload-a-file), [rotate tokens](#rotate-tokens), [convert money and dates](#convert-money-and-dates), [log requests and collect metrics](#log-requests-and-collect-metrics), [use an Experimental method](#use-an-experimental-method).

**Your app:** [use it in Rails](#use-it-in-rails), [forking web servers and job runners](#forking-web-servers-and-job-runners), [receive webhooks in Rails](#receive-webhooks-in-rails), [test your own app](#test-your-own-app).

**Pennylane:** [run an export](#run-an-export), [read the changelogs](#read-the-changelogs), [letter and unletter ledger entry lines](#letter-and-unletter-ledger-entry-lines), [categorise with weights](#categorise-with-weights), [subscribe to webhooks](#subscribe-to-webhooks), and one section per resource group from [customer invoices](#work-with-customer-invoices) to [purchase orders](#import-a-purchase-order).

## Walk a list

Every `list`, and every method that lists what belongs to one record (`invoice_lines`, `payments`, `contacts`), returns an `Enumerator::Lazy`. Nothing is sent until you read it. It asks for the next page only when you read past the current one:

<!-- example -->
```ruby
invoices = client.customer_invoices.list        # no request yet

invoices.each { |invoice| puts invoice[:invoice_number] }   # every page, one at a time
invoices.first(10)                              # one request
invoices.to_a                                   # every page, into one Array
invoices.map { _1[:amount] }.first(3)           # lazy: stops after the page with the third item
```

Each read starts again from the first page. Keep the Array from `to_a` if you need the items twice.

`client.paginate(:operationId, **params)` does the same for any list operation by its operationId. `client.pages` returns one Hash per page instead, with `items`, `has_more` and `next_cursor`:

<!-- example -->
```ruby
client.paginate(:getCustomerInvoices, sort: "-date").first(5)

client.pages(:getCustomerInvoices).each do |page|
  puts "#{page[:items].size} invoices, more: #{page[:has_more]}"
end
```

Each page asks for the largest `limit` the operation allows: 100, or 1000 for the changelogs, ledger accounts and trial balance. That spends as few calls from the rate limit as it can. Pass a smaller `limit:` for smaller pages; a limit outside what the operation allows raises `ArgumentError`:

<!-- example -->
```ruby
client.customer_invoices.list(limit: 20).first(20)   # one request for 20 items
```

Read a list with `each`, `first`, `take`, `map` or `to_a`. Avoid `next`, `peek` and `zip`: a list read that way opens a connection of its own, which stays open until garbage collection.

## Filter and sort a list

Pennylane filters a list with `filter`, an array of conditions. Each condition is a Hash with a `field`, an `operator` and a `value`. Pass it as an Array of Hashes; the client sends the JSON string Pennylane expects:

<!-- example -->
```ruby
recent_credit_notes = [
  { field: "date", operator: "gteq", value: "2024-01-01" },
  { field: "credit_note", operator: "eq", value: "true" }
]
client.customer_invoices.list(filter: recent_credit_notes, sort: "-date").to_a
```

Each list operation documents which fields it filters on and which operators each field takes, in the `filter` parameter of its reference page (see the [checklist](api/CHECKLIST.md) for the operationId). For customer invoices, for example:

- `id`, `date`, `customer_id`, `billing_subscription_id`, `quote_id`: `lt`, `lteq`, `gt`, `gteq`, `eq`, `not_eq`, `in`, `not_in`
- `invoice_number`, `flow_id`: `eq`, `not_eq`, `in`, `not_in`
- `draft`, `credit_note`: `eq`, with `"true"` or `"false"`
- `external_reference`: `eq`
- `category_id`: `in`

Other operations add `start_with`, for example on a ledger account `number`. Most of Pennylane's own examples send the value as a String, dates and booleans included (`"2024-01-01"`, `"true"`). The contract snapshot has no example of an `in` value, so check its shape against your sandbox before you rely on it.

Use the fields the operation's reference page lists. Pennylane's pagination guide filters customer invoices on `status`, but the reference page for `getCustomerInvoices` does not list that field; `draft` is the one it lists.

`sort` takes one field, with `-` in front for descending order: `sort: "-id"`. Each operation lists the fields it sorts on. Pennylane's cursor does not remember the filter or the sort, so the client sends both again with every page.

## Retry a request

The client sends a request again only when that cannot do harm:

| Answer | GET | POST, PUT, DELETE |
|---|---|---|
| 429 | retried after `retry-after` | retried after `retry-after` |
| 500, 502, 503, 504 | retried | raised |
| `ConnectionError`, `TimeoutError` | retried | raised |
| anything else | raised | raised |

A call makes at most 3 attempts, with a random backoff (up to 0.5 s, then up to 1 s), and waits at most 30 s in total. A `retry-after` that would pass the 30 s raises `RateLimitError` at once, with `retry_after` set. Change the cap per client:

<!-- example -->
```ruby
client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"), max_retry_wait: 10)
```

A write that failed with a 5xx or a timeout is not sent again, because Pennylane may have applied it and does not de-duplicate writes. When you know a write is safe to repeat, opt in per call with `retry: :always`. Every named write takes it, as does `client.call`. It defaults to `nil`, which keeps the rule above. Anything else raises `ArgumentError`. `retry` is never sent to Pennylane:

<!-- example -->
```ruby
client.category_groups.update(42, label: "Sales", retry: :always)   # setting a label twice is harmless
client.customer_invoices.categorize(42, [{ id: 426, weight: "1" }], retry: :always)
client.call(:putCategoryGroup, id: 42, label: "Sales", retry: :always)
```

Reads need nothing: every GET is retried as the table shows. So a named read takes no `retry:`. A list refuses it with an `ArgumentError` that says a GET is retried already. A `find` has no keywords at all, so `find(42, retry: :always)` raises Ruby's own `ArgumentError`, "wrong number of arguments".

Do not pass `retry: :always` to a create: a retried create can make two records.

## Stay inside the rate limit

Pennylane allows 25 requests per 5 seconds per token. The client keeps one bucket per token for the whole process, shared by every client and thread, and corrects it from the `ratelimit-remaining` and `ratelimit-reset` headers on every response. When the bucket is empty, a call waits for the window to reset. Threads need nothing more:

<!-- example -->
```ruby
threads = [42, 43, 44, 45].map do |id|
  Thread.new { client.customer_invoices.find(id) }
end
threads.map(&:value).map { _1[:invoice_number] }
```

Each wait fires a `type: :wait` event with the seconds waited; see [log requests](#log-requests-and-collect-metrics).

### Share the budget across processes

The bucket is per process. Several processes on one token (Puma workers, Sidekiq processes) each think they have 25 requests. The rate-limit headers and the 429 retries absorb the overlap, at the cost of some 429s. To share one budget, give the client a `LimiterRegistry` that builds your own limiter, for example on Redis. A limiter responds to two methods:

- `acquire`: wait until a call is allowed, then return the seconds waited (`0.0` when there was no wait);
- `update(remaining:, reset_at:)`: take Pennylane's count from the headers; `reset_at` is a Unix time, or `nil`.

`idle?` is optional; see below the example.

<!-- example -->
```ruby
class SharedLimiter
  def initialize(key)
    @key = key   # e.g. the Redis key for this token's window
  end

  # Take one call from the shared window, sleeping until it resets when it is empty.
  def acquire
    0.0
  end

  # Lower the shared count to Pennylane's, and remember when the window ends.
  def update(remaining:, reset_at:); end
end

limiters = PennylaneClient::LimiterRegistry.new { |key| SharedLimiter.new("pennylane:#{key}") }
client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"), limiters:)
client.users.me
```

The block given to `LimiterRegistry.new` gets a SHA-256 hex digest of the token, never the token. Build the registry once and share it; every client given it shares its limiters. The registry drops a limiter no one has fetched for 60 s (`idle_after:` changes it) and builds a new one the next time the token is used. If your limiter responds to `idle?`, it is dropped only when that returns true.

## Set timeouts

The default transport waits 5 s to connect and 30 s to read or write. An upload gets 300 s to read and write. Build your own `NetHttpTransport` to change them, once, and pass it to every client:

<!-- example -->
```ruby
TRANSPORT = PennylaneClient::NetHttpTransport.new(open_timeout: 3, read_timeout: 60, upload_timeout: 600)

client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"), transport: TRANSPORT)
client.users.me
```

A transport holds its connections, one per host per thread or fiber, so share one rather than build one per client. `keep_alive_timeout:` (10 s) is how long an idle connection is kept. `close` closes the calling thread's connections.

A timeout raises `TimeoutError`, after the retries a GET gets. A write that timed out may still have been applied.

## Upload a file

Pass a `Pathname`, a `File` or an IO as the file. A file on disk is streamed, so a 100 MB upload does not load 100 MB into memory. The filename comes from the path and the content type from the extension (`.pdf`, `.png`, `.jpg`, `.jpeg`, `.tif`, `.tiff`, `.bmp`, `.gif`, `.xml`):

<!-- example -->
```ruby
attachment = client.file_attachments.upload(Pathname("receipt.pdf"))
attachment[:id]   # pass as file_attachment_id: to an import or a ledger entry

File.open("timesheet.pdf", "rb") do |file|
  client.customer_invoices.upload_appendix(42, file)
end
```

Hash and Array fields go as JSON parts:

<!-- example -->
```ruby
client.customer_invoices.import_e_invoice(Pathname("invoice.xml"), invoice_options: { customer_id: 42 })
```

### Upload a file you built in memory

A PDF you generate in memory has no path, so it has no filename and no content type. Wrap it in `PennylaneClient::Upload` to give it both, and rewind it first:

<!-- example upload_from_memory -->
```ruby
pdf = StringIO.new
pdf.write("%PDF-1.4\n")   # your PDF library writes the document here
pdf.write("%%EOF\n")
pdf.rewind                # back to the first byte

upload = PennylaneClient::Upload.new(pdf, filename: "receipt-2026-09.pdf", content_type: "application/pdf")
client.file_attachments.upload(upload)[:id]
```

The client reads an IO from where it stands when the call starts, to its end. A `StringIO` you have written to stands at its end, so without `rewind` the file part is empty, and nothing raises. A retry after a 429 goes back to the same starting point, so every attempt sends the same bytes.

`Upload.new(io, filename:, content_type:)` takes both keywords as optional. With only `filename:`, the content type comes from its extension. An IO with no path sent without an `Upload` goes as `upload`, with `application/octet-stream`, and a `filename:` field next to it does not change that. Each upload operation's reference lists the content types Pennylane accepts: for `file_attachments.upload`, a PDF or a PNG, JPEG, TIFF, BMP or GIF image.

The file is always positional. A `file:` keyword next to it raises `ArgumentError`, as a keyword naming a positional id does.

A file you open stays open; the client closes only what it opened from a `Pathname`. A `Pathname` is checked before anything is sent: a missing file raises `Errno::ENOENT`, and a directory or a file you cannot read raises `ArgumentError`. An IO must respond to `size`, so a pipe cannot be uploaded.

## Rotate tokens

`token:` takes a String, or anything that responds to `call` and returns the current token. The client asks for it once per call, so a token you refresh elsewhere takes effect on the next call. The client never refreshes a token itself; a rejected token raises `AuthenticationError`:

<!-- example unauthorized_once -->
```ruby
class TokenStore
  def self.current = ENV.fetch("PENNYLANE_TOKEN")   # read it from your database or cache
  def self.refresh!; end                           # your OAuth refresh
end

client = PennylaneClient.new(token: -> { TokenStore.current })

begin
  client.users.me
rescue PennylaneClient::AuthenticationError
  TokenStore.refresh!
  client.users.me
end
```

A String token is checked when the client is built, and a provider's token on each call: one that is empty or has a space or a line break raises `ArgumentError`, and the message never quotes it. Rotating tokens do not grow memory: the limiter of a token no one has used for 60 s is dropped.

## Convert money and dates

Pennylane sends amounts as decimal Strings and dates as ISO 8601 Strings. The gem returns them unchanged. [Read money and dates](getting-started.md#read-money-and-dates) says what each amount field of an invoice means:

<!-- example -->
```ruby
require "bigdecimal"
require "date"

invoice = client.customer_invoices.find(42)
BigDecimal(invoice[:amount])        # "230.32" -> 0.23032e3
Date.iso8601(invoice[:date])        # "2023-08-30"
Time.iso8601(invoice[:updated_at])  # "2023-08-30T10:08:08.146343Z"
```

On Ruby 3.4 and newer `bigdecimal` is a bundled gem, so add `gem "bigdecimal"` to your own Gemfile. The client never requires it.

Send amounts as Strings too. An Integer or a Float goes as a JSON number, and Pennylane's error guide lists "amounts not sent as strings" as a cause of a 400. The client converts a `BigDecimal`, `Date`, `Time` or `DateTime` you pass, anywhere in the body or the query:

<!-- example -->
```ruby
client.transactions.create(bank_account_id: 42, label: "Rent", date: Date.new(2026, 9, 30),
                           amount: BigDecimal("-1200.50"))   # sends "2026-09-30" and "-1200.5"
```

A `Time` keeps its fraction of a second, to the microsecond. So a changelog's `processed_at`, parsed with `Time.iso8601` and passed back as `since:`, is sent as Pennylane wrote it.

## Log requests and collect metrics

<!-- example -->
```ruby
require "logger"

PennylaneClient.configure do |config|
  config.logger = Logger.new($stdout)
  config.on_request = ->(event) { puts "#{event[:type]} #{event[:operation_id]} #{event[:status]}" }
end

client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))
client.users.me   # logs "pennylane_client getMe GET /api/external/v2/me -> 200 (84.2 ms)"
```

Configure before building clients: a client reads the configuration when it is built. `PennylaneClient.new(token:, logger:, on_request:)` overrides it for one client.

Each attempt sent to Pennylane, each retry and each rate-limit wait writes one log line and fires one event, a frozen Hash. `type` says which:

<!-- not run: event Hashes, not code -->
```ruby
{ type: :request, operation_id: :getMe, method: "GET", path: "/api/external/v2/me", status: 200, error: nil, duration: 84.2 }
{ type: :retry, operation_id: :getMe, method: "GET", path: "/api/external/v2/me", attempt: 2, wait: 0.3, status: 503, error: nil }
{ type: :wait, operation_id: :getMe, method: "GET", path: "/api/external/v2/me", wait: 0.8 }
```

For a request, `status` is `nil` and `error` names the error class when no response arrived, and `duration` is milliseconds on the wire. A retry names the attempt about to be sent and what the last one got. `wait` is in seconds. The path has no query string, and the token is never in an event or a log line. A logger or callback that raises is reported with `warn` and never fails the call.

## Use an Experimental method

A few methods wrap an operation, or an input, that Pennylane marks Hidden, alpha or beta. They work like any other, but may change in a minor release. The [Stability](../README.md#stability) section lists them, and each carries `@note Experimental` in its documentation. Pin a minor version if you depend on one:

<!-- not run: a Gemfile line -->
```ruby
# Gemfile
gem "pennylane_client", "~> 1.2.0"   # 1.2.x only; a minor release may change an Experimental method
```

Prefer the stable alternative where there is one:

<!-- example -->
```ruby
address = { address: "8 rue de la paix", postal_code: "75002", city: "Paris", country_alpha2: "FR" }

client.customers.create_company(name: "Acme", billing_address: address)                 # stable
client.customers.create(customer_type: "company", name: "Acme", billing_address: address)   # Experimental
```

## Use it in Rails

Configure the gem in an initializer:

<!-- example rails -->
```ruby
# config/initializers/pennylane.rb
require "pennylane_client"

PennylaneClient.configure do |config|
  config.logger = Rails.logger
  config.on_request = lambda do |event|
    ActiveSupport::Notifications.instrument("request.pennylane", event)
  end
end
```

Build a client where you need one. Clients are cheap: every client shares the same connections, one per thread or fiber, and every client on one token shares one rate-limit budget per process. Puma in cluster mode and other forking servers need no setup; see [forking web servers and job runners](#forking-web-servers-and-job-runners). With one Pennylane company per tenant, build one client per token:

<!-- example rails -->
```ruby
class PennylaneAccount
  def initialize(token)
    @token = token
  end

  def client
    @client ||= PennylaneClient.new(token: @token)
  end
end

account = PennylaneAccount.new(ENV.fetch("PENNYLANE_TOKEN"))
account.client.customer_invoices.find(42)
```

In a background job, build the client in `perform` and let an error raise, so the job's own retry takes over. Rescue what a retry cannot fix:

<!-- example sidekiq -->
```ruby
class FinalizeInvoiceJob
  include Sidekiq::Job

  def perform(invoice_id)
    client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))
    client.customer_invoices.finalize(invoice_id)
  rescue PennylaneClient::ValidationError, PennylaneClient::NotFoundError => e
    Rails.logger.warn("invoice #{invoice_id} not finalized: #{e.message}")
  end
end
```

A job retry sends a write again. The client refuses to resend a write after a 5xx or a timeout because Pennylane may have applied it, and a job retry has the same risk. Make the job check before it writes (read the invoice, and skip it if it is already final) when a second run could do harm.

Rate-limit waits happen inside the job's thread. With many workers on one token, see [share the budget across processes](#share-the-budget-across-processes).

## Forking web servers and job runners

Puma in cluster mode, Unicorn, Passenger's smart spawning, Resque and Spring load your app once and then fork worker processes. The gem handles the fork itself. You add nothing to `on_worker_boot`, `after_fork` or `before_fork` for it.

What happens in a forked child:

- **Connections.** Each connection is tagged with the process that opened it. A child never sends a request on a connection it inherited, even one the parent opened at boot (a `users.me` check in an initializer, for example). It opens its own on its first call. It does not close the inherited ones either: they are the parent's sockets, and closing one would end the parent's TLS session. `NetHttpTransport#close` in a child closes only the child's own connections.
- **Clients.** A client built before the fork works in the child. So does the configuration set with `PennylaneClient.configure`.
- **Rate limit.** The budget is per process. Each child starts with a copy of the parent's bucket as it was at the fork, and spends it on its own. Four Puma workers on one token each allow themselves 25 requests per 5 s. Pennylane's rate-limit headers and the 429 retries absorb the overlap. To share one budget between processes, see [share the budget across processes](#share-the-budget-across-processes).

Resque forks a new child for each job, so each job opens its own connection and makes its own TLS handshake.

## Receive webhooks in Rails

Pennylane signs each delivery with `X-Pennylane-Signature: t=<unix seconds>,v1=<hex>`. `PennylaneClient::Webhook.verify!` checks it and returns the event:

<!-- example rails_webhook -->
```ruby
# config/routes.rb: post "/pennylane/webhooks", to: "pennylane_webhooks#create"
class PennylaneWebhooksController < ApplicationController
  skip_forgery_protection

  def create
    event = PennylaneClient::Webhook.verify!(request.raw_post, request.headers["X-Pennylane-Signature"],
                                             secret: ENV.fetch("PENNYLANE_WEBHOOK_SECRET"))
    PennylaneDelivery.create!(delivery_id: event[:id])   # a unique index on delivery_id
    PennylaneEventJob.perform_later(event[:event], event[:data])
    head :ok
  rescue ActiveRecord::RecordNotUnique
    head :ok             # delivered before: acknowledge it and do nothing
  rescue PennylaneClient::SignatureError
    head :bad_request
  end
end
```

- **Pass the raw body.** `request.raw_post` is the bytes as received. Parsing and re-serialising the JSON changes the bytes, and the signature will not match.
- **De-duplicate on the delivery id.** Delivery is at least once and in no particular order. `event[:id]` is the delivery id. The controller above stores it under a unique index and acknowledges a repeat without doing the work again. Make the job idempotent as well, and reconcile state from the payload, not from the order of arrival.
- **Answer fast.** Return a 2xx within a few seconds and do the work in a job. A slow answer counts as a failed delivery and is sent again.

`verify!` computes the HMAC-SHA256 of `"{t}.{raw_body}"` with the subscription secret, compares it in constant time, and rejects a `t` more than 300 seconds from now (`tolerance:` changes it; `nil` skips the check). In a test, `now:` (a `Time` or Unix seconds) sets the time it checks against, so a recorded delivery still verifies. It returns the event as a deep-frozen Hash with symbol keys:

<!-- example webhook -->
```ruby
event = PennylaneClient::Webhook.verify!(raw_body, signature, secret: ENV.fetch("PENNYLANE_WEBHOOK_SECRET"))
event[:id]                      # => 987654, the delivery id
event[:event]                   # => "customer_invoice.e_invoicing_status_updated"
event[:data][:object][:id]      # => 42
event[:data][:previous_attributes]
```

A missing or malformed header, a signature that does not match, a stale timestamp or a body that is not a JSON object raises `SignatureError`, never anything else. `SignatureError` never carries the secret or the expected digest. A blank secret raises `ArgumentError`, because that is a bug in your code, not a bad delivery.

## Test your own app

The gem sends plain HTTPS requests, so [WebMock](https://github.com/bblimke/webmock) can stand in for Pennylane in your tests. Stub the method and path from the operation's reference page (the [checklist](api/CHECKLIST.md) lists them) and answer with the JSON Pennylane documents. The examples below are Minitest with `require "webmock/minitest"`.

First, a client that never waits on the rate limit. Every client shares one budget per token for the whole process, 25 requests per 5 s, and a test suite spends it fast. A fresh `LimiterRegistry` gives a test its own budget, but it still waits once that test makes more than 25 calls in 5 s. A registry that builds a limiter doing nothing never waits:

<!-- example -->
```ruby
module NoopLimiter
  def self.acquire = 0.0                        # the seconds waited: none
  def self.update(remaining:, reset_at:); end   # ignores Pennylane's rate-limit headers
end

client = PennylaneClient.new(token: "test-token", limiters: PennylaneClient::LimiterRegistry.new { NoopLimiter })
```

### Stub one record

<!-- example continued -->
```ruby
api = "https://app.pennylane.com/api/external/v2"
json = { "Content-Type" => "application/json" }

stub_request(:get, "#{api}/customer_invoices/42")
  .to_return(status: 200, headers: json,
             body: { id: 42, invoice_number: "F20230001", amount: "230.32", status: "upcoming" }.to_json)

client.customer_invoices.find(42)[:invoice_number]   # => "F20230001"
```

### Stub a list

A list asks for the largest page the operation allows (`limit=100` here) and sends your `filter` as a JSON string. Each page answers with `items`, `has_more` and `next_cursor`. The client asks for the next page with `cursor` set to the last `next_cursor`, and stops when `has_more` is false:

<!-- example continued -->
```ruby
drafts = [{ field: "draft", operator: "eq", value: "true" }]

stub_request(:get, "#{api}/customer_invoices")
  .with(query: { limit: "100", filter: drafts.to_json })
  .to_return(status: 200, headers: json, body: {
    items: [{ id: 42, invoice_number: "F20230001", amount: "230.32", currency: "EUR" }],
    has_more: true, next_cursor: "cursor-2"
  }.to_json)
stub_request(:get, "#{api}/customer_invoices")
  .with(query: { limit: "100", filter: drafts.to_json, cursor: "cursor-2" })
  .to_return(status: 200, headers: json, body: {
    items: [{ id: 43, invoice_number: "F20230002", amount: "120.00", currency: "EUR" }],
    has_more: false, next_cursor: nil
  }.to_json)

client.customer_invoices.list(filter: drafts).map { _1[:id] }.to_a   # => [42, 43]
```

### Stub an error

Answer with the status and the body Pennylane sends. This 422 body is the example from Pennylane's error guide:

<!-- example continued -->
```ruby
stub_request(:post, "#{api}/customer_invoices")
  .to_return(status: 422, headers: json, body: {
    error: "unprocessable_entity", message: "Missing required field: customer_id",
    details: { field: "customer_id", issue: "is required" }
  }.to_json)

begin
  client.customer_invoices.create(date: "2026-09-30", deadline: "2026-10-30", invoice_lines: [])
rescue PennylaneClient::ValidationError => e
  e.details   # => { field: "customer_id", issue: "is required" }
end
```

A GET that gets a 500, 502, 503 or 504 is sent 3 times, with up to 1.5 s of random backoff in all, before `ServerError` is raised. Build the test client with `max_retry_wait: 0` and it raises on the first one: no backoff fits in 0 s. A 429 stubbed with `"Retry-After" => "0"` is still retried, at once:

<!-- example continued -->
```ruby
stub_request(:get, "#{api}/customer_invoices/44").to_return(status: 503)
no_waits = PennylaneClient.new(token: "test-token", max_retry_wait: 0,
                               limiters: PennylaneClient::LimiterRegistry.new { NoopLimiter })

begin
  no_waits.customer_invoices.find(44)
rescue PennylaneClient::ServerError => e
  e.status   # => 503
end
```

### Point the client at a local server

`base_url:` sends every request to another host, such as a fake Pennylane you run in your test suite. The client adds `/api/external/v2`. It is for tests; leave the default, `https://app.pennylane.com`, everywhere else:

<!-- example continued -->
```ruby
local = PennylaneClient.new(token: "test-token", base_url: "http://127.0.0.1:9292",
                            limiters: PennylaneClient::LimiterRegistry.new { NoopLimiter })
stub_request(:get, "http://127.0.0.1:9292/api/external/v2/me").to_return(status: 200, headers: json, body: "{}")
local.users.me   # => {}
```

### Without WebMock

Without WebMock, give the client a transport of your own. A transport is anything with `call(request)` that returns a `PennylaneClient::Response`:

<!-- example -->
```ruby
class CannedTransport
  attr_reader :requests

  def initialize(body)
    @body = body
    @requests = []
  end

  def call(request)
    @requests << request   # verb, url, headers, body, operation_id
    PennylaneClient::Response.new(status: 200, headers: { "content-type" => "application/json" }, body: @body)
  end
end

transport = CannedTransport.new('{"id":42,"invoice_number":"F20230001"}')
client = PennylaneClient.new(token: "test-token", transport:, limiters: PennylaneClient::LimiterRegistry.new)
client.customer_invoices.find(42)
transport.requests.last.operation_id   # => :getCustomerInvoice
```

A test transport answers with a status; it never raises for one. To simulate no answer, raise `PennylaneClient::TimeoutError` or `PennylaneClient::ConnectionError` from `call`.

## Run an export

`client.exports` covers the FEC, General Ledger and Analytical General Ledger exports. Pennylane builds an export in the background. `generate_*` asks for one, then reads it until it is ready:

<!-- example export_ready -->
```ruby
export = client.exports.generate_fec(period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 6, 30))
export[:status]     # => "ready"
export[:file_url]   # download it within 30 minutes; the URL expires
```

It reads the export straight away, then every 5 s, for up to 300 s. Change both with `interval:` and `timeout:`. It raises `ExportError` when the export ends in `error`, or when it is still pending and the next read would come after `timeout`. It never waits past `timeout`, so it can give up as much as one `interval` before it. The error's `export` is the export as last read, so you can check on it later:

<!-- example export_error -->
```ruby
begin
  client.exports.generate_general_ledger(period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 6, 30),
                                         timeout: 60)
rescue PennylaneClient::ExportError => e
  e.export[:status]   # => "error"
  e.export[:id]       # => 124
end
```

A read that fails on its own (a 5xx after its retries, or no response) raises that error instead, without the export id. To keep the id through anything, or to poll on your own schedule, call the two halves yourself:

<!-- example -->
```ruby
export = client.exports.create_analytical_general_ledger(period_start: Date.new(2026, 1, 1),
                                                          period_end: Date.new(2026, 6, 30), mode: "in_column")
client.exports.find_analytical_general_ledger(export[:id])[:status]   # "pending", "ready" or "error"
```

The same pairs exist for the others: `create_fec` and `find_fec`, `create_general_ledger` and `find_general_ledger`. `mode:` is `"in_line"`, the default, or `"in_column"`.

## Read the changelogs

`client.changelogs` has one change feed per record type: `customer_invoices`, `customers`, `ledger_entries_categories`, `ledger_entry_lines`, `ledger_entry_lines_categories`, `products`, `quotes`, `supplier_invoices`, `suppliers` and `transactions`. Each returns the changes lazily, oldest `processed_at` first. A change carries the record's `id` and its `operation` (`"insert"`, `"update"` or `"delete"`), not the record itself:

<!-- example -->
```ruby
client.changelogs.customer_invoices(since: Time.now - 3600).each do |change|
  next if change[:operation] == "delete"

  invoice = client.customer_invoices.find(change[:id])
  puts "#{invoice[:invoice_number]} is now #{invoice[:status]}"
end
```

Pass `since:` as a `Time` or an RFC 3339 String such as `"2026-09-29T10:00:00Z"`. A `DateTime` works too. A `Time` is sent with its own UTC offset (`"2026-09-29T11:00:00+01:00"`), which is also RFC 3339. Anything else raises `ArgumentError`, a `Date` included: Pennylane's `start_date` is a date-time, and its reference does not say it takes a bare date. For the changes since the start of a day, pass `Date.new(2026, 9, 29).to_time`.

Without `since:` the feed starts at the oldest change Pennylane keeps. Pennylane keeps four weeks of changes, and a `since:` older than that raises `ValidationError` (422).

`since:` is the only spelling. Pennylane calls the parameter `start_date`, and `start_date:` raises `ArgumentError`. The client sends `start_date` with the first page only, because Pennylane answers 400 to `start_date` next to a `cursor`.

To resume where the last run stopped, keep the `processed_at` of the last change you handled and pass it as `since:` next time. The last page's `next_cursor` is null, so it cannot carry you forward. Pass `processed_at` back as the String, or as a `Time` parsed from it; either keeps its microseconds. The contract does not say whether `since:` includes a change at that exact time, so handle a repeat of the last change:

<!-- example -->
```ruby
saved = (Time.now - 600).utc.iso8601(6)   # read from your database
last_seen = nil

client.changelogs.supplier_invoices(since: saved).each do |change|
  puts "#{change[:operation]} supplier invoice #{change[:id]}"
  last_seen = change[:processed_at]
end
saved = last_seen if last_seen            # write back to your database
```

## Letter and unletter ledger entry lines

Lettering matches ledger entry lines that settle each other, such as an invoice line and its payment. `letter` and `unletter` take the lines as an Array of `{ id: }` and require `unbalanced_lettering_strategy:`. `"none"` makes Pennylane refuse an unbalanced lettering with a `ValidationError`; `"partial"` allows it:

<!-- example -->
```ruby
lines = client.ledger_entry_lines

lettering = lines.letter([{ id: 91 }, { id: 95 }], unbalanced_lettering_strategy: "none")
lettering.map { _1[:id] }   # every line of the lettering

lines.lettered_lines(91).to_a
lines.unletter([{ id: 95 }], unbalanced_lettering_strategy: "none")   # => true
```

Lettering a line that is already lettered brings its whole lettering along. `unletter` is a DELETE with a body and returns true. A missing `unbalanced_lettering_strategy:` raises `ArgumentError` before anything is sent.

## Categorise with weights

Analytical categories are shared out by weight. `categorize` replaces a record's categories with the ones you pass, as a bare Array of `{ id:, weight: }`. Within one category group the weights must add up to 1. Send weights as Strings:

<!-- example -->
```ruby
split = [{ id: 426, weight: "0.6575" }, { id: 427, weight: "0.3425" }]   # one group: adds up to 1

client.customer_invoices.categorize(42, split)
client.supplier_invoices.categorize(42, split)
client.customers.categorize(42, split)
client.suppliers.categorize(42, [{ id: 426, weight: "1" }])
client.transactions.categorize(42, [{ id: 59, weight: "0.5" }, { id: 33, weight: "0.5" }, { id: 65, weight: "1" }])
client.ledger_entry_lines.categorize(42, [])   # removes them all
```

Categories from different groups can be mixed, as in the transaction above, where two groups each add up to 1. Each record type also has `categories(id)`, which lists what it has now. The categories themselves are managed with `client.categories` and `client.category_groups`; see [categories and products](#work-with-categories-and-products).

## Subscribe to webhooks

`client.webhook_subscriptions` manages where Pennylane sends events. Webhooks are beta at Pennylane, which suggests the changelogs as a fallback, so every `webhook_subscriptions` method is [Experimental](../README.md#stability). `Webhook.verify!` is stable.

<!-- example -->
```ruby
hook = client.webhook_subscriptions.create(callback_url: "https://example.com/pennylane/webhooks",
                                           events: ["customer_invoice.e_invoicing_status_updated"])
hook[:secret]   # store it now: no other call returns it
```

The create response is the only place the secret appears. `find` and `list` leave it out, and `update` takes no secret. The contract has no way to rotate it; create a new subscription and delete the old one to get a new secret. The events are `customer_invoice.e_invoicing_status_updated`, `dms_file.created` and `supplier_invoice.e_invoicing_received`. A company-scoped token allows 10 subscriptions per company; an app-bound token allows 10 in all.

Pennylane can disable a subscription whose callback URL keeps failing. `find(id)` shows `enabled`, `disabled_reason` and `consecutive_failures`. `update(id, enabled: true)` sends the flag to turn it back on; the contract does not say whether that works after a `permanent_error`.

## Work with customer invoices

`client.customer_invoices` names every Customer Invoices operation. Most names say what they do (`find`, `update`, `finalize`, `mark_as_paid`). These are the ones you would not guess.

Every list walks all its pages lazily, including the ones under one invoice. `appendices` and `categories` take no `sort:`; the others do:

<!-- example -->
```ruby
invoices = client.customer_invoices

invoices.invoice_lines(42).each { |line| puts "#{line[:label]}: #{line[:amount]}" }
invoices.payments(42, sort: "-id").first(5)
# also: invoice_line_sections, matched_transactions, custom_header_fields, appendices, categories
```

`list` yields the invoices only. With `include: "invoice_lines"`, Pennylane adds an `included` section to each page, and `list` drops it. Read the pages to keep it. Pennylane marks `include` experimental, so it may change or go away:

<!-- example -->
```ruby
page = client.pages(:getCustomerInvoices, include: "invoice_lines").first
page[:items]      # the invoices
page[:included]   # the invoice lines, when Pennylane sends them
```

`send_by_email` and `send_to_pa` raise `ConflictError` while Pennylane is still generating the PDF or processing an e-invoice import. The client never retries a 409, so try again later. Both return true:

<!-- example -->
```ruby
client.customer_invoices.send_by_email(42)                                     # to the customer's addresses
client.customer_invoices.send_by_email(42, recipients: ["billing@example.com"])
client.customer_invoices.send_to_pa(42)                                        # to the Partner Dematerialization Platform
```

Three ways to bring in an invoice issued elsewhere:

<!-- example -->
```ruby
invoices = client.customer_invoices
pdf = client.file_attachments.upload(Pathname("invoice.pdf"))

invoices.create_from_quote(quote_id: 42, draft: true)
invoices.import(file_attachment_id: pdf[:id], customer_id: 42, date: Date.new(2026, 9, 1), deadline: Date.new(2026, 10, 1),
                currency_amount_before_tax: "100.00", currency_tax: "20.00", currency_amount: "120.00",
                invoice_lines: [{ label: "Audit", quantity: 1, unit: "piece", raw_currency_unit_price: "100.00",
                                  vat_rate: "FR_200", currency_amount: "120.00", currency_tax: "20.00" }])
invoices.import_e_invoice(Pathname("facturx.pdf"), invoice_options: { customer_id: 42 })
```

`import` stores the amounts exactly as sent, so they must add up. `import_e_invoice` takes a Factur-X PDF, or a UBL or CII XML invoice, and streams it like any [upload](#upload-a-file). Pennylane calls the XML input alpha, so it is [Experimental](../README.md#stability). `upload_appendix(42, file)` attaches a PDF or image to an invoice the same way.

`link_credit_note(42, credit_note_id: 43)` links credit note 43 to invoice 42. `mark_installment_as_paid(42, 3)` marks one installment paid; Pennylane tags it Hidden and alpha, so it is [Experimental](../README.md#stability).

## Work with customers

`client.customers` names every Customers operation. Pennylane keeps company and individual customers apart. `list` and `find` return both, and each item's `customer_type` says which. Create and update through the kind:

<!-- example -->
```ruby
customers = client.customers
address = { address: "8 rue de la paix", postal_code: "75002", city: "Paris", country_alpha2: "FR" }

acme = customers.create_company(name: "Acme", billing_address: address)
ada  = customers.create_individual(first_name: "Ada", last_name: "Lovelace", billing_address: address)

customers.update_company(acme[:id], payment_conditions: "30_days")
customers.update_individual(ada[:id], emails: ["ada@example.org"])
customers.find_company(acme[:id])     # also find_individual; find(id) works for either
```

Contacts belong to one customer, so every contact method takes the customer id first. A contact is its own record. Adding, changing or deleting one does not touch the customer's invoice recipients (`emails`):

<!-- example -->
```ruby
customers = client.customers

customers.contacts(42, sort: "-id").each { |contact| puts contact[:email] }
contact = customers.create_contact(42, first_name: "Grace", last_name: "Hopper", email: "grace@example.org")
customers.update_contact(42, contact[:id], first_name: "Rear Admiral Grace")
customers.delete_contact(42, contact[:id])
```

## Work with supplier invoices and suppliers

`client.supplier_invoices` and `client.suppliers` name every Supplier Invoices and Suppliers operation. A supplier invoice has no `create`. It comes in by import, from a PDF uploaded first with `client.file_attachments.upload`, or from an e-invoice file:

<!-- example -->
```ruby
invoices = client.supplier_invoices
pdf = client.file_attachments.upload(Pathname("invoice.pdf"))

invoices.import(file_attachment_id: pdf[:id], supplier_id: 42, date: Date.today, deadline: Date.today + 30,
                currency_amount_before_tax: "100", currency_amount: "120", currency_tax: "20",
                invoice_lines: [{ currency_amount: "120", currency_tax: "20", vat_rate: "FR_200" }])
invoices.import_e_invoice(Pathname("facturx.pdf"), invoice_options: { supplier_id: 42 })
```

Pennylane de-duplicates supplier invoice files: importing the same file twice raises `ConflictError`. `import` also raises `ConflictError` while the uploaded file is not ready yet; Pennylane says to try again after a few seconds. The client never retries a 409. A `ConflictError` that persists most likely means the file was imported before.

`ValidateAccountingSupplierInvoice` is `validate_accounting(42)`. Payment status and e-invoice status take their value as a keyword:

<!-- example -->
```ruby
invoices = client.supplier_invoices

invoices.update_payment_status(42, payment_status: "paid")        # or "to_be_paid"; returns true
invoices.update_e_invoice_status(42, status: "disputed", reason: "incorrect_vat_rate")
invoices.update_e_invoice_status(42, status: "refused", reason: "duplicate_invoice")   # archives it for good
invoices.update_e_invoice_status(42, status: "approved")          # lifts a dispute
```

`update_e_invoice_status` is for invoices received through the PA. A transition the invoice cannot make, such as disputing one with payments, raises `ValidationError`.

`update` takes `invoice_lines:` as `{ create: [...], update: [...], delete: [...] }`, not a plain array. `link_purchase_request(42, purchase_request_id: 8)` links one purchase request; call it once for each. The lists under one invoice walk every page lazily: `invoice_lines`, `payments`, `matched_transactions` (all take `sort:`) and `categories` (no `sort:`).

Suppliers have `list`, `find`, `create`, `update`, `categories` and `categorize`. `create` needs `name:` and raises `ConflictError` when the supplier already exists.

## Work with mandates

The Mandates operations split into three resources, one per kind of mandate:

- `client.sepa_mandates`: `list`, `find`, `create`, `update`, `delete`
- `client.gocardless_mandates`: `list`, `find`, `send_request`, `associate`, `cancel`
- `client.pro_account_mandates`: `list`, `send_request`, `migration_candidates`, `migrate`

A SEPA mandate is one you record yourself. `create` needs `customer_id:`, `iban:`, `bic:`, `identifier:` and `signed_at:`:

<!-- example -->
```ruby
client.sepa_mandates.create(customer_id: 42, iban: "FR7630006000011234567890189", bic: "AGRIFRPP",
                            identifier: "MANDATE-1", signed_at: Date.new(2026, 9, 1), sequence_type: "RCUR")
```

For GoCardless, `send_request` emails a customer a link to set up a mandate; `email:` needs `recipients:`. `associate` links an existing mandate to a customer. `cancel` works only on a `pending_submission`, `submitted` or `active` mandate; Pennylane rejects any other with a 400 or 422, both `ValidationError`. All three return true:

<!-- example -->
```ruby
mandates = client.gocardless_mandates
mandates.send_request(customer_id: 42, email: { recipients: ["billing@acme.example"], subject: "Direct debit" })
mandates.associate(5, customer_id: 42)
mandates.cancel(5)
```

Pro Account mandates need a Pennylane Pro Account and an enabled merchant profile. Without the Pro Account every call raises `NotFoundError`; without the merchant profile, `PermissionError`. `client.company.features` does not report either today, so the 404 or 403 is the check. `migrate` moves a SEPA or GoCardless mandate to the Pro Account; only a candidate with status `available` can migrate. Its answer wraps the migration in `mandate_migration:`. `send_request` returns true:

<!-- example -->
```ruby
pro = client.pro_account_mandates
pro.migration_candidates(filter: [{ field: "status", operator: "eq", value: "available" }]).first
pro.migrate(mandate_type: "SepaMandate", mandate_id: 3)[:mandate_migration]   # "Mandate" for a GoCardless one
pro.send_request(customer_id: 42)
```

## Work with transactions and bank accounts

`client.transactions`, `client.bank_accounts` and `client.bank_establishments` name every Transactions and bank operation. A transaction lives in a bank account; `create` needs `bank_account_id:`, `label:`, `date:` and `amount:`:

<!-- example -->
```ruby
account = client.bank_accounts.create(name: "Main account", iban: "FR7630006000011234567890189")
tx = client.transactions.create(bank_account_id: account[:id], label: "Card payment", date: Date.today, amount: "-12.50")

client.transactions.update(tx[:id], supplier_id: 42)   # the third party, and nothing else
```

Bank accounts have `list`, `find` and `create`, and no update or delete. `account_type: "current"` is deprecated; use `"checking"`. A bank account's optional `bank_establishment_id:` is an id from `client.bank_establishments.list`.

`update` sets the transaction's third party. Pass `customer_id:` or `supplier_id:`, not both. Both are nullable in the contract, so `nil` sends `null` (not yet checked against the sandbox).

Match a transaction from the invoice's side. Call `match_transaction` once per transaction; one transaction can match several invoices. Customer invoices must not be drafts. Each call returns true:

<!-- example -->
```ruby
client.customer_invoices.match_transaction(42, transaction_id: 7)
client.customer_invoices.unmatch_transaction(42, transaction_id: 7)
client.supplier_invoices.match_transaction(51, transaction_id: 7)   # also unmatch_transaction
client.transactions.matched_invoices(7).to_a                       # the other way round
```

`categories` and `matched_invoices` take no `sort:`.

## Work with quotes and commercial documents

`client.quotes` and `client.commercial_documents` name every Quotes and Commercial Documents operation. A commercial document is a proforma, a shipping order or a purchasing order; `document_type:` says which, and it cannot change later:

<!-- example -->
```ruby
lines = [{ label: "Audit", quantity: 2, raw_currency_unit_price: "450", unit: "day", vat_rate: "FR_200" }]

quote = client.quotes.create(customer_id: 42, date: Date.today, deadline: Date.today + 30, invoice_lines: lines)
client.commercial_documents.create(document_type: "proforma", customer_id: 42, date: Date.today,
                                   deadline: Date.today + 30, invoice_lines: lines)

client.quotes.update_status(quote[:id], status: "accepted")
client.quotes.send_by_email(quote[:id], recipients: ["billing@example.com"])
client.customer_invoices.create_from_quote(quote_id: quote[:id], draft: true)
```

Pennylane numbers each document from the company's numbering for its type. Without one, it refuses to create that commercial document, number a quote or finalise a customer invoice. Numberings are configured in the Pennylane app; `client.numberings.list` shows which exist: `estimate` for quotes, `proforma`, `shipping_order` and `purchasing_order` for commercial documents, `invoice` for customer invoices.

`update` takes `invoice_lines:` as `{ create: [...], update: [...], delete: [...] }`, not a plain array. A commercial document's `invoice_line_sections:` works the same way. A quote's `update_status` takes `"pending"`, `"accepted"`, `"denied"`, `"invoiced"` or `"expired"`. `send_by_email` works like the invoice one: it returns true, and raises `ConflictError` while Pennylane is still generating the PDF.

Both resources list what hangs off one document: `invoice_lines` and `invoice_line_sections` (both take `sort:`) and `appendices` (no `sort:`). `upload_appendix(id, file)` attaches a PDF or image, streamed like any [upload](#upload-a-file). `client.customer_invoice_templates.list` lists the customer invoice templates; the API has no call to create or change one.

## Work with the ledger

`client.journals`, `client.ledger_accounts`, `client.ledger_entries`, `client.ledger_entry_lines`, `client.fiscal_years`, `client.trial_balance` and `client.file_attachments` name every ledger operation.

A ledger entry needs a journal and balanced lines. Amounts are Strings or BigDecimals. `create` takes the lines as a plain array; `update` takes them as `{ create: [...], update: [...], delete: [...] }`:

<!-- example -->
```ruby
bank = client.ledger_accounts.list(filter: [{ field: "number", operator: "eq", value: "512" }]).first
entry = client.ledger_entries.create(date: Date.today, label: "Rent", journal_id: 42,
                                     ledger_entry_lines: [{ debit: "1200", credit: "0", ledger_account_id: 21 },
                                                          { debit: "0", credit: "1200", ledger_account_id: bank[:id] }])
client.ledger_entries.update(entry[:id], ledger_entry_lines: { update: [{ id: 91, label: "Rent, March" }] })
```

Pennylane may return the lines in a different order from the one you sent. Match them by debit, credit or label, not by position. A ledger account number starting with 401 also creates a supplier, and one starting with 411 a company customer.

Lines are listed, [lettered](#letter-and-unletter-ledger-entry-lines) and [categorised](#categorise-with-weights) on `client.ledger_entry_lines`. The trial balance needs a period. It comes back one Hash per account, 1000 to a page:

<!-- example -->
```ruby
client.trial_balance.list(period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 12, 31))
                    .each { puts [_1[:number], _1[:debits], _1[:credits]].join("\t") }
```

To attach a receipt to an entry, upload it with `client.file_attachments.upload` and pass the id as `file_attachment_id:`. The contract says that field will soon be deprecated. The deprecated `postLedgerAttachments` has no named method.

## Work with categories and products

`client.categories`, `client.category_groups` and `client.products` name every Categories, Category Groups and Products operation.

An analytical category lives in a category group. Create the group first; its `kind:` is `"profit_and_loss"`, `"treasury"` or `"building"`. A treasury category also takes `direction:`, which defaults to `"cash_out"`:

<!-- example -->
```ruby
group = client.category_groups.create(label: "Teams", kind: "profit_and_loss")
client.categories.create(label: "Marketing", category_group_id: group[:id], analytical_code: "MKT")
client.category_groups.categories(group[:id]).map { _1[:label] }
```

`category_groups.update` requires `label:` even when you change only `kind:`. `categories.update` takes `label:`, `analytical_code:` and `direction:`; it does not move a category to another group. To put a category on a record, use [`categorize`](#categorise-with-weights).

A product needs `label:`, `price_before_tax:` and `vat_rate:`. Invoice and quote lines can point at it with `product_id:`:

<!-- example -->
```ruby
client.products.create(label: "Consulting day", price_before_tax: BigDecimal("650"), vat_rate: "FR_200",
                       unit: "day", reference: "CONS-DAY")
client.products.list(filter: [{ field: "reference", operator: "eq", value: "CONS-DAY" }]).first
```

## Check the token and the company

`client.users.me` returns the token's `:user`, `:company` and `:scopes`. `:user` can be nil; the contract does not say when. `:scopes` lists what the token may do.

Some features depend on the company's plan or on a rollout. `client.company.features` says which are on. Check it before you send a gated field, because Pennylane does not always refuse one it cannot honour:

<!-- example -->
```ruby
invoice = { customer_id: 42, date: Date.today, deadline: Date.today + 60, draft: true,
            invoice_lines: [{ label: "Audit", quantity: 1, unit: "day", raw_currency_unit_price: "900", vat_rate: "FR_200" }] }

if client.company.features[:installments]
  halves = [{ deadline: Date.today + 30, amount: "540.00" }, { deadline: Date.today + 60, amount: "540.00" }]
  client.customer_invoices.create(**invoice, installments: halves)   # they add up to the total with tax
else
  client.customer_invoices.create(**invoice)
end
```

With `installments` off, an invoice sent with installments either gets a 403 or is created with a single installment. Pennylane adds keys to `features` as it gates new features.

`client.pa_registrations.list` returns the company's registrations with a Plateforme Agréée. The company has finished PA onboarding when a registration is `"activated"` with the `exchange_direction` you need. A nil `siret` is the head office (SIREN). Like every `list`, it returns an `Enumerator::Lazy`. Reading it is one request, because Pennylane takes no cursor for it. If Pennylane answers `has_more: true`, reading raises `PennylaneClient::Error` rather than return part of the list.

## Work with billing subscriptions

`client.billing_subscriptions` names every Billing Subscriptions operation. Pennylane issues a customer invoice on each occurrence of the recurring rule.

The request shape differs from what you read back. Send `mode:` as a Hash and `recurring_rule:` with `type:`; read back `mode` as a String and `recurring_rule[:rule_type]`. Send `customer_id:`; read back `customer: { id:, url: }`:

<!-- example -->
```ruby
line = { label: "Hosting", quantity: 1, unit: "month", raw_currency_unit_price: BigDecimal("49.90"), vat_rate: "FR_200" }
subscription = client.billing_subscriptions.create(
  start: Date.new(2026, 10, 1), customer_id: 42, payment_conditions: "30_days", payment_method: "offline",
  mode: { type: "email", email_settings: { recipients: ["billing@example.com"] } },
  recurring_rule: { type: "monthly", interval: 1, day_of_month: 1 },
  customer_invoice_data: { invoice_lines: [line] }
)

client.billing_subscriptions.update(subscription[:id], customer_invoice_data: {
  invoice_lines: { create: [line], update: [{ id: 11, quantity: 2 }], delete: [{ id: 12 }] }
})
client.billing_subscriptions.update(subscription[:id], stop: true)   # stop: false resumes it
```

`mode:` is `{ type: "awaiting_validation" }`, `{ type: "finalized" }` or the email form above. The email form needs an email template set up in Pennylane. `invoice_lines(id)` and `invoice_line_sections(id)` walk the current lines and sections.

## Import a purchase order

`client.purchase_requests` lists and reads purchase requests, and `import` creates one from a purchase order. Upload the order first and pass the attachment id. Pennylane approves an imported request straight away:

<!-- example -->
```ruby
attachment = client.file_attachments.upload(Pathname("po-1042.pdf"))
client.purchase_requests.import(
  file_attachment_id: attachment[:id], supplier_id: 42, reason: "Laptops", purchase_order_number: "PO-1042",
  currency_amount_before_tax: BigDecimal("1000"), currency_tax: BigDecimal("200"), currency_amount: BigDecimal("1200"),
  delivery_address: { address: "1 rue de Rivoli", postal_code: "75001", city: "Paris", country_alpha2: "FR" },
  purchase_request_lines: [{ label: "Laptop", quantity: 2, unit: "piece", unit_price: BigDecimal("500"),
                             vat_rate: "FR_200", currency_amount: BigDecimal("1200"), currency_tax: BigDecimal("200") }]
)
```
