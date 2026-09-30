# Architecture

How the gem is put together, and why. Written for someone about to change the code. If the code and this document disagree, the code wins and this document has a bug.

The design is in [proposal 0001](../proposals/0001-pennylane-client-gem.md), decisions D1 to D11, and drawn in the [design diagram](architecture/design-diagram.md). For using the gem, read [getting started](getting-started.md) and the [how-to recipes](how-to.md).

## Components

One class, one job. Every component in `lib/` is built.

| Component | File | Its one responsibility |
|---|---|---|
| `PennylaneClient` | `lib/pennylane_client.rb` | The namespace. `PennylaneClient.new` builds a Client; `PennylaneClient.configure` sets the process-wide defaults. |
| `Client` | `client.rb` | Wiring. It composes the middleware around the Transport, hands calls to the Executor, and returns one Resource per group. No logic of its own. |
| `Resources::Resource` and one subclass per resource group | `resources/` | Named operations. Each public method is a hand-written one-liner over `call` or `paginate` (D3). |
| `Operation` | `operation.rb` | One Operation as plain data: operationId, verb, path, `paginated`, `max_limit`, body kind, success code, `deprecated`. |
| `OPERATIONS` | `operations.rb` | The generated operation table: every Operation in the latest contract snapshot, one per line. Never edited by hand. |
| `Registry` | `registry.rb` | Frozen lookup from operationId to Operation. An unknown id raises `UnknownOperationError`. |
| `Executor` | `executor.rb` | Operation and params to a `Request`; the final `Response` to a return value or an Error. |
| `Encoder` | `encoder.rb` | Request values to the form Pennylane wants: `BigDecimal` to a plain decimal String, `Date`, `Time` and `DateTime` to ISO 8601. |
| `Multipart`, `Upload` | `multipart.rb` | A multipart/form-data body that streams its files from disk. `Upload` lets the caller set a file's name and content type. |
| `Request`, `Response` | `request.rb`, `response.rb` | Plain values passed to and from a Transport. |
| `Middleware::Auth` | `middleware/auth.rb` | Adds the `Authorization` header. The only holder of the token. |
| `Middleware::Retry` | `middleware/retry.rb` | Sends a call again when that is safe (D5). |
| `Middleware::RateLimit` | `middleware/rate_limit.rb` | Keeps each token inside 25 requests per 5 s. |
| `Middleware::Instrument` | `middleware/instrument.rb` | Records each attempt that reaches the Transport as one event. |
| `Limiter` | `limiter.rb` | The token bucket for one token. |
| `LimiterRegistry` | `limiter_registry.rb` | One Limiter per token, shared by every Client in the process, with idle ones dropped. |
| `NetHttpTransport` | `net_http_transport.rb` | The default Transport, on `Net::HTTP`: keep-alive connections, timeouts, no retries. |
| `ConnectionOwners` | `connection_owners.rb` | Which fiber owns which connections, so those of finished threads and fibers can be closed. |
| `Paginator` | `paginator.rb` | Walks a cursor-paginated list for `paginate` and `pages`. |
| `Instrumentation` | `instrumentation.rb` | Turns an event into one log line and one `on_request` call. Never raises. |
| `Configuration` | `configuration.rb` | Holds `logger` and `on_request`, read when a Client is built. |
| `Error` and subclasses | `errors.rb` | One class per documented status, plus `ConnectionError`, `TimeoutError`, `ExportError` and `SignatureError`. |
| `Webhook` | `webhook.rb` | `verify!` checks an inbound delivery's signature and returns the event. It uses no Client. |
| `VERSION` | `version.rb` | The gem version. |

Files are under `lib/pennylane_client/` unless the path says otherwise.

Dev-time tools live in `tools/` and are never shipped:

| Tool | File | Job | Run by |
|---|---|---|---|
| `SnapshotContract` | `tools/snapshot_contract.rb` | Builds the dated [contract snapshot](api/README.md) in `docs/api/contract/<date>/`. | `rake contract:snapshot` |
| `ContractDrift` | `tools/contract_drift.rb` | Compares Pennylane's docs with the latest snapshot. The weekly workflow opens a `drift` issue. | `rake contract:drift` |
| `OperationTable` | `tools/operation_table.rb` | Generates `operations.rb` from the latest snapshot. | `rake contract:sync` |
| `Checklist` | `tools/checklist.rb` | Generates [`docs/api/CHECKLIST.md`](api/CHECKLIST.md) and the README's live-verified count. | `rake checklist` |
| `Stale` | `tools/stale.rb` | Fails the gate when a generated file differs from what its generator writes. | `rake stale` |
| `Smoke` | `tools/smoke.rb`, `tools/live_reports.rb` | Paced sandbox checks and the reports they write to `docs/api/live/`. | `rake smoke` |

`FakePennylane` and `FakePennylane::Server` (`test/support/`) are a Pennylane stand-in for tests and for `rake load` and `rake stress` ([performance](performance.md)).

## The request path

What happens on `client.call(:getJournal, id: 42)`:

1. **Client** takes `retry:` out of the params (`nil` or `:always`; anything else raises `ArgumentError`) and hands the rest to the Executor.
2. **Registry** turns `:getJournal` into its Operation. A typo raises `UnknownOperationError` before anything is sent.
3. **Executor** builds a `Request`: verb, URL, headers, body, `operation_id` and `retry_policy`. The path and body rules are below.
4. **Middleware** runs, outermost first. Client composes it in `Client#initialize`:

   ```
   Auth -> Retry -> RateLimit -> Instrument -> Transport
   ```

   - **Auth** adds `Authorization: Bearer <token>`. The token is a String, or a provider (`#call`) asked once per call, not once per attempt. A token that is empty or has whitespace or a line break raises `ArgumentError` without echoing it, when the Client is built or when a provider returns it.
   - **Retry** sends the attempt again when that is safe (D5). A 429 is retried for any verb, after `retry-after` seconds, or after a backoff when the header is missing. A 500, 502, 503, 504, `ConnectionError` or `TimeoutError` is retried for GET only, or for any verb when the call has `retry_policy: :always`. At most 3 attempts. The backoff is full jitter: a random wait up to 0.5 s, then up to 1 s. All waits in one call stay within `max_retry_wait:` (30 s); a wait that would pass the cap is not taken and the last answer stands, so a long `retry-after` surfaces as `RateLimitError`. Each retry emits a `:retry` event.
   - **RateLimit** takes a call from the token's Limiter before each attempt, waiting when the bucket is empty, and emits a `:wait` event when it waited. It reads `ratelimit-remaining` and `ratelimit-reset` from every response and corrects the bucket. Retry sits outside RateLimit, so every attempt takes its own call from the bucket.
   - **Instrument** sits next to the Transport and records each attempt as a `:request` event, answered or not. `duration` never includes a wait.
5. **Transport** sends the request and returns a `Response`, or raises `ConnectionError` or `TimeoutError`. It never raises for an HTTP status.
6. **Instrumentation** takes every event: one log line (`info`, or `warn` for a retry or when no response came) and one frozen `on_request` call. It never raises: a failing logger or callback is reported with `warn` and ignored, so a write that reached Pennylane never looks failed to the caller.
7. **Executor** reads the final `Response`; see [Responses and errors](#responses-and-errors).

A named method takes the same path. `client.journals.find(42)` is `call(:getJournal, id: 42)`.

## Building the request

### Path parameters

Names in the path template (`{id}`) are taken from the params, run through the Encoder, and escaped with `URI.encode_uri_component`. The Executor raises `ArgumentError` before anything is sent when a path parameter is:

- missing;
- nil or empty, because it would leave an empty segment, and `GET /customer_invoices/` is the list;
- exactly `.` or `..`, because a server may resolve a dot segment to another Operation. Dots inside a value (`"a.b"`) are sent escaped as usual.

A named method that takes path parameters positionally goes through `Resource#call_on` or `#paginate_on`. These keep the positional ids apart from the caller's keywords and raise `ArgumentError` when a keyword names one of them. Merged, `products.update(1, id: 2)` would write record 2.

### Body and query

What happens to the params left after the path depends on the Operation's body kind:

- **JSON body.** Every other param is the body, run through the Encoder and `JSON.generate`. This covers `DELETE` with a body (`deleteLedgerEntryLinesUnletter`). Six Operations (`putCustomerCategories` and its siblings) take a JSON array, which keywords cannot build, so the caller passes the body positionally: `client.call(:putCustomerCategories, [...], customer_id: 9)`. Keywords then fill only the path; any left over raise `ArgumentError`. A Hash body that names a path parameter raises `ArgumentError` too. A `body:` keyword is an ordinary param, sent as a field named `body`.
- **Multipart body** (the 7 upload Operations). Every other param is a form field of a `Multipart`. A File, IO, Pathname or `Upload` is a file part, streamed rather than read into memory (an IO from its position when the call starts); a Hash or Array is an `application/json` part; nil is left out; anything else is text. The size is known up front, so the request carries a `Content-Length`. A missing Pathname raises `Errno::ENOENT`, and a directory or unreadable file raises `ArgumentError`, both before anything is sent. Files the Executor opened from a Pathname are closed when the call is over.
- **No body.** Every other param goes into the query. nil values are left out. Hash and Array values are sent as JSON strings, because Pennylane's `filter` is a JSON array in a query string. Passing a positional body raises `ArgumentError`.

No Operation in the 2026-09-30 snapshot takes both a body and a query.

### Encoding

`Encoder` converts only what Pennylane would otherwise get in the wrong form (D6):

- `BigDecimal` becomes `to_s("F")`, `"230.32"`, not `"0.23032e3"`.
- `Date` becomes `"2026-06-30"`. `Time` and `DateTime` become ISO 8601. A fraction of a second is kept to the microsecond (`"2025-06-25T11:54:18.589480Z"`), so a changelog resumed from a parsed `processed_at` starts where it stopped. A whole second is sent without a fraction.
- Hashes and Arrays are walked. Everything else passes through.

It requires nothing: `bigdecimal` is a bundled gem, so it handles only the classes the caller has already loaded.

### Headers

`Accept: application/json`, a `User-Agent` naming the gem and Ruby version, and a `Content-Type` when there is a body. No token: Auth adds it later.

## Responses and errors

The Executor reads the final `Response`:

- 2xx (200 to 299) with an empty body returns `true`.
- 2xx with a body returns `JSON.parse(body, symbolize_names: true, freeze: true)`: a deep-frozen Hash with symbol keys, values as Pennylane sent them.
- 2xx with a body that is not JSON, or not valid UTF-8, raises the base `Error`. A 2xx body with bad bytes is not scrubbed: a record read with U+FFFD in place of its bytes could be written back that way. JSON must be UTF-8 (RFC 8259), so such a body is not JSON.
- Any other status raises `Error.from_response`: 400 and 422 `ValidationError`, 401 `AuthenticationError`, 403 `PermissionError`, 404 `NotFoundError`, 409 `ConflictError`, 429 `RateLimitError`, any 5xx `ServerError`, anything else (a 3xx, a 418) the base `Error`.

`Error` is built from the response alone, never the request, so the token cannot reach a message. Pennylane sends error bodies in several shapes (`guides/errors.md` in the snapshot), and each is parsed defensively:

```
{"error": "unprocessable_entity", "message": "...", "details": {...}}   code, message, details
{"status": 409, "error": "A document with ID ... already exists."}      message
{"message": "..."}                                                      message
plain text, or nothing                                                  the text, or the status alone
```

The message is `"422 unprocessable_entity: Entry lines are not balanced"`, with the text cut at 200 characters. `#status`, `#code`, `#details`, `#body` and `#headers` carry the rest. An error body that is not valid UTF-8 (a proxy's Latin-1 error page) is read with the bad bytes replaced by U+FFFD, so the class still follows the status and `rescue PennylaneClient::ServerError` still catches it. `#body` keeps the bytes as they came.

`RateLimitError#retry_after` reads the `retry-after` header. `ConnectionError` and `TimeoutError` come from the Transport, with no status. `ExportError` comes from the exports poll and carries the export as last read. `SignatureError` comes from `Webhook.verify!`. `UnknownOperationError` is an `ArgumentError`, not an `Error`: it is a bug in the caller, raised before any request.

## Rate limiting

Pennylane allows 25 requests per 5 s per token and reports its window in every response ([guide](api/contract/2026-09-30/guides/rate-limiting.md)).

- **Limiter.** A token bucket of 25 calls per 5 s window, refilled in full when the window ends. `acquire` takes a call or sleeps until the reset, and returns the seconds slept. `update(remaining:, reset_at:)` corrects it from the headers. The count only ever goes down: another process may be spending the same token, and requests in flight are not in Pennylane's count yet. The lock is held to take a call or read a header, never while sleeping.
- **Clock skew.** `ratelimit-reset` is a Unix time, so the Limiter uses wall-clock seconds. A reset already past, or more than one window plus a second away, means the clocks disagree: it is ignored and the bucket keeps its own window end. `ratelimit-remaining` does not depend on the clock, so it is applied either way. Skew costs at most one window.
- **LimiterRegistry.** One Limiter per token, keyed by the SHA-256 hex digest of the token, never the token. `LimiterRegistry.default` is shared by every Client in the process, so every Client and thread on one token shares one budget. A limiter is built outside the registry's lock, so a slow custom limiter never blocks other tokens; when two threads race, the first one stored wins.
- **Eviction.** Tokens rotate (an OAuth provider) and multi-company apps hold one per company, so the registry drops limiters no one has fetched for `idle_after` seconds (60 by default). A Limiter is dropped only once its window has ended and no thread waits on it (`idle?`); a new one is then a full bucket, the same as the old. A custom limiter that does not answer `idle?` is dropped on time alone. The sweep runs when a new limiter is stored, at most once per `idle_after`, so a fetch of a known token does no extra work.
- **Your own limiter.** `LimiterRegistry.new { |key| RedisLimiter.new(key) }` builds any object with `acquire` and `update(remaining:, reset_at:)`, for a budget shared across processes.

## The Transport and connections

A Transport is anything with `call(request) -> Response` that raises `ConnectionError` or `TimeoutError` when no response arrives and never raises for an HTTP status. `Request#body` is a String, nil, or for an upload a `Multipart`, which reads like an IO (`read`, `rewind`, `size`); rewind it before sending.

`NetHttpTransport` is the default. Every Client shares `NetHttpTransport.default`, so building a Client per request or per token opens no new sockets. The token travels in each request, not in the connection.

- **One connection per host per fiber.** Connections live in `Thread.current[...]`, which is fiber-local, so threads and fibers never share a socket and a call on an open connection takes no lock.
- **Timeouts.** Open 5 s, read 30 s, write 30 s. An upload gets 300 s to read and write (`upload_timeout:`), and the connection goes back to 30 s afterwards.
- **Keep-alive.** An idle connection is kept for 10 s (`keep_alive_timeout:`), not `Net::HTTP`'s 2 s, because a rate-limit wait lasts up to 5 s and would otherwise cost a new connection and TLS handshake after every wait ([performance](performance.md)). `Net::HTTP` still replaces a connection the server has closed.
- **No retries.** `max_retries = 0`. `Net::HTTP` otherwise resends an idempotent verb once on a dropped connection, and PUT and DELETE have side effects at Pennylane (D5).
- **Bodies.** A `Multipart` body is rewound before each attempt, so a retry after a 429 sends the same bytes as the first attempt, and handed to `Net::HTTP` as `body_stream`. Response bodies are tagged UTF-8; the bytes are checked later, by the Executor and `Error`.

### Connection lifecycle

- **A call that does not complete drops its connection.** `NetHttpTransport#call` closes the connection in an `ensure` unless a response was read. That covers `ConnectionError` and `TimeoutError`, and also any exception the transport does not rescue: `Timeout.timeout`, rack-timeout, `Interrupt`. Without it, a request sent and its answer unread would leave that answer on the socket, to be read as the next call's response, and the next call could be for another token.
- **Finished fibers' connections are reaped.** `ConnectionOwners` maps each fiber, held weakly in an `ObjectSpace::WeakMap`, to its connections. Whenever any thread or fiber opens a new connection, the connections of every fiber that is no longer alive are closed. A finished fiber never runs again, so no call is using them. A thread per job therefore does not leave one socket per finished job. The owners' lock is taken only when a fiber first connects and when a connection is opened.
- **`close`** closes the current thread's (fiber's) connections.

## Pagination

`client.paginate(:getCustomerInvoices, filter: [...])` builds a Paginator around the Executor. Each page is an ordinary call through the whole pipeline, so each page takes its own call from the rate limit and GETs retry as usual. The rules ([guide](api/contract/2026-09-30/guides/cursor-pagination.md)):

- **Largest page.** It asks for the Operation's `max_limit` (100 or 1000, read from the contract by the generator) unless the caller passed a smaller `limit`. A `limit` outside 1 to `max_limit` raises `ArgumentError` before anything is sent.
- **Every param on every page.** The cursor does not remember `filter` or `sort`, so every param goes again next to `cursor`.
- **Except `start_date`.** Every changelog Operation answers 400 to `start_date` next to `cursor`, so it goes with the first request only, and passing both `start_date` and `cursor` raises `ArgumentError`. The named changelog methods take `since:` and raise `ArgumentError` on `start_date:`.
- **Stops** when `has_more` is false or `next_cursor` is null.
- **Loops are refused.** A page that returns the cursor it was given raises `Error`, rather than ask for the same page forever.
- **Lazy.** It returns an `Enumerator::Lazy`: reading the first ten items sends one request. Enumerating it again starts from the first page. `client.pages` gives the page Hashes (`items`, `has_more`, `next_cursor`) instead of the items.
- **One-page lists.** `getPaRegistrations` answers with `items`, `has_more` and `next_cursor` but takes no cursor, so an Operation that is not paginated is read as one page, sent as given. If that page says `has_more: true`, the rest cannot be asked for, and the walk raises `Error` rather than return part of the list.
- **Refusals.** A response without an `items` Array raises `Error`. An Operation that is not a GET raises `ArgumentError`, and so does `retry:`, because a GET is retried already.

Every named `list` and nested list returns this `Enumerator::Lazy`, `pa_registrations.list` included.

## Where the token lives

Only `Middleware::Auth` holds the token, and only `Request#headers` carries it, from Auth inward.

- `Client`, `Executor`, `Auth`, `Request` and `Resources::Resource` override `inspect`, as do `Limiter`, `LimiterRegistry`, `ConnectionOwners`, `Paginator` and `Multipart`. `Request#inspect`, `#to_s` and `#pretty_print` filter the `Authorization` header.
- Errors are built from the response alone. Events are built from the Operation and the URL path, never the query or the headers.
- Rate-limit keys are SHA-256 digests.
- `Request#to_h` and `#headers` do return the raw header, because a Transport needs it. A custom Transport must not log them.

`test/token_secrecy_test.rb` checks all of these.

## Exports and webhooks

- **Exports.** `exports.generate_*` creates the export, reads it straight away, then every `interval` seconds (5) until its `status` is `ready`, and returns it. It raises `ExportError` when the status is `error` or the export is not ready within `timeout` (300 s); the error's `#export` has the id to read later. `retry:` applies to the create only; the reads are GETs.
- **Webhooks.** `Webhook.verify!(raw_body, signature_header, secret:)` parses `X-Pennylane-Signature: t=<unix seconds>,v1=<hex>`, computes HMAC-SHA256 of `"{t}.{raw_body}"`, and compares each 64-character `v1` with `OpenSSL.fixed_length_secure_compare`. It rejects a timestamp more than `tolerance` (300 s) from now, either way, and a body that is not a JSON object. Everything it rejects raises `SignatureError`; a blank secret raises `ArgumentError`. The header is read as bytes, so no header can raise anything else.

## Public API, Experimental tier and the private boundary

- **Public (D10).** The README's [Public API](../README.md#public-api) section lists exactly what SemVer covers: `PennylaneClient.new` and `configure` with `Configuration`, `Client` (`call`, `paginate`, `pages` and the resource accessors), every named method, the error classes, `Webhook.verify!`, `Upload`, `LimiterRegistry` and the limiter interface, the Transport interface with `Request` and `Response`, `NetHttpTransport` and its constructor options, and `VERSION`.
- **Private.** Every other constant under `PennylaneClient` is tagged `@api private` where it is defined, including `Operation`, `OPERATIONS`, `Registry`, `Executor`, `Encoder`, `Multipart`, `Paginator`, `Limiter`, `Instrumentation`, `ConnectionOwners`, `STATUS_ERRORS`, the Middleware classes and `Resources::Resource`. The Multipart part classes are `private_constant`. `test/public_api_test.rb` fails on a new constant that is neither listed nor tagged.
- **Experimental (D9).** A named method that wraps an Operation or input Pennylane marks Hidden, alpha or beta carries `@note Experimental:` in its YARD comment and is listed in the README's [Stability](../README.md#stability) section. It may change in a minor release. `test/stability_test.rb` keeps the two lists equal.

## Design rationale

The reasoning is recorded as decisions in [proposal 0001](../proposals/0001-pennylane-client-gem.md#decisions). The short version:

- **D1. `pennylane_client`, module `PennylaneClient`.** The `pennylane` gem already defines `Pennylane::Client`; one module named after the gem cannot clash with it.
- **D2. Clean room.** Built only from Pennylane's public documentation and observed sandbox behaviour. See [CONTRIBUTING.md](../CONTRIBUTING.md#the-clean-room-rule).
- **D3. Generated table, hand-written names, `call` for everything.** Every Operation is reachable from the snapshot on day one. Ruby names are chosen by a person, each born from a failing behaviour test, and survive Pennylane renaming an operationId. No metaprogramming.
- **D4. Current RubyGems and Bundler conventions.** Ruby 3.3 and newer, RBS in `sig/`, Trusted Publishing.
- **D5. Never retry POST, PUT or DELETE after a 5xx or no response.** Pennylane does not enforce idempotency on creates, so the client cannot know whether the first attempt ran. A 429 is retried for every verb because it should mean the request was not run.
- **D6. Raw values.** Responses are deep-frozen Hashes. Money and dates stay strings, so no field list drifts and no `bigdecimal` dependency is needed.
- **D7. No token refresh inside the client.** `token:` takes a provider, asked once per call; a 401 raises `AuthenticationError`.
- **D8. Ordinary open source, unofficial.**
- **D9. Experimental tier.** The gem cannot promise more than Pennylane does about Hidden, alpha and beta Operations.
- **D10. A declared public surface.** Everything else is `@api private`, so internals can change without a major release.
- **D11. Every named write takes `retry:`.** The opt-in of D5, with one spelling on every write.

## Where this design would strain

Known limits, stated plainly:

- **Several processes share one token's budget.** The default limiter is per process. Header correction and 429 retries absorb the overflow ([measured](performance.md): four processes, 48 calls, 3 answered 429 and all 48 succeeded). A budget shared across processes needs a limiter you inject yourself.
- **The bucket follows Pennylane's window, not a sliding one.** It refills in full when the window ends, as `ratelimit-reset` describes. Until the first response, the local window may not line up with Pennylane's; the headers then move it. `ratelimit-reset` is whole seconds, so the local reset can be up to a second off (an open question in proposal 0001).
- **Header correction needs a roughly correct clock.** With the host clock more than about a second off Pennylane's, every reset looks implausible and is ignored. `ratelimit-remaining` still drains the bucket, but the bucket keeps its own window end. Keep NTP running.
- **A write can race a server closing an idle connection.** `Net::HTTP` checks whether the server has closed a connection before reusing it. If the server closes it between that check and the request, a POST, PUT or DELETE fails with `ConnectionError` and is not retried, even though Pennylane never saw it. Keeping idle connections for 10 s, not longer, keeps this rare. Pennylane's own idle timeout is not documented.
- **External iteration opens a connection per walk.** `paginate(...).next` (and `zip`, or anything else that drives an Enumerator from outside) runs the walk in its own fiber, so each walk opens its own connection and TLS handshake. Ruby keeps that fiber alive until GC collects the enumerator, even after the last page, so the reaper cannot see it as finished and its socket stays open until then. Sharing the thread's connection with that fiber would need a lock on every call. Iterate with `each`, `first` or `to_a` to reuse the thread's connection.
- **Reaping waits for the next new connection.** A finished thread's sockets close when another thread or fiber opens a connection, or when GC collects the fiber. A process that stops opening connections keeps them until then.
- **One Operation shape is assumed.** The Executor puts leftover params in the body when there is one and in the query when there is not. No Operation in the snapshot takes both. If a future snapshot adds one, its query params would go in the body; neither the generator nor the Executor checks for it.
- **Named lists return items only.** `list` walks `items` and drops any other top-level key on the page, such as the `included` section `getCustomerInvoices` returns with `include:` (experimental at Pennylane). `client.pages` returns the whole page.
- **A path-less IO uploads as `application/octet-stream`.** A `StringIO` or a Tempfile without an extension has no name to take a content type from. Pennylane lists the content types it allows; wrap the IO in `Upload.new(io, filename:, content_type:)`.
- **An IO is read from its current position.** `Multipart` records the position of each IO when the call starts and rewinds to it before every attempt, so a retry sends what the first attempt sent. An IO left at its end (a `StringIO` just written to) sends an empty file part without an error. Rewinding to byte 0 instead would ignore a position the caller chose, and Ruby reads an IO from where it stands elsewhere too (`IO.copy_stream`, `Net::HTTP` `body_stream`).
- **D5 rests on an assumption.** A 429 is retried for writes because it should mean the request was not run. That is unconfirmed until a sandbox run (`PENNYLANE_SMOKE_PROBE_429`, proposal 0001 open questions).
- **No live verification yet.** The maintainer has no Pennylane account, so behaviour is checked against the documentation and `FakePennylane`, not a sandbox. The README states the live-verified count.
- **Responses are untyped.** Callers convert money and dates themselves (D6).
