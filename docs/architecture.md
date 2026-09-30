# Architecture

How the gem is put together, and why. Written for someone about to change the code. If the code and this document disagree, the code wins and this document has a bug.

> The gem is being built. This document describes what exists today and points to the plan for the rest. The full design is in [proposal 0001](../proposals/0001-pennylane-client-gem.md) and drawn in the [design diagram](architecture/design-diagram.md).

## What exists today

| Component | File | Role |
|---|---|---|
| `PennylaneClient` | `lib/pennylane_client.rb` | The namespace. |
| `PennylaneClient::VERSION` | `lib/pennylane_client/version.rb` | Gem version. |
| `PennylaneClient::Operation` | `lib/pennylane_client/operation.rb` | One Operation as plain data: operationId, verb, path, paginated, largest page size (`max_limit`), body kind, success code, deprecated. |
| `PennylaneClient::OPERATIONS` | `lib/pennylane_client/operations.rb` | The generated operation table: every Operation in the latest snapshot, one row per line. Every live Operation is Registered here. |
| `PennylaneClient::Client` | `lib/pennylane_client/client.rb` | Wiring only. `PennylaneClient.new(token:)` composes the middleware; `#call(:operationId, **params)` reaches any Registered operation. |
| `PennylaneClient::Resources::Resource` and one subclass per resource group | `lib/pennylane_client/resources/` | Named operations. Each public method is a hand-written one-liner over `Client#call` or `#paginate`, e.g. `def finalize(id) = call(:finalizeCustomerInvoice, id:)`. A method that takes path parameters positionally goes through `call_on` or `paginate_on`, e.g. `def update(id, **attributes) = call_on(:putProduct, { id: }, **attributes)`, which raises `ArgumentError` when a keyword names one of them; merged, the keyword would replace the positional id. The base class holds the Client and no state. `client.customer_invoices` returns one instance per Client. Together they name every live operation: `CustomerInvoices`, `Customers`, `SupplierInvoices`, `Suppliers`, `SepaMandates`, `GocardlessMandates`, `ProAccountMandates`, `BankAccounts`, `BankEstablishments`, `Transactions`, `Quotes`, `CommercialDocuments`, `CustomerInvoiceTemplates`, `Numberings`, `Journals`, `FiscalYears`, `FileAttachments`, `LedgerAccounts`, `LedgerEntries`, `LedgerEntryLines`, `TrialBalance`, `Categories`, `CategoryGroups`, `Products`, `Changelogs`, `Exports`, `BillingSubscriptions`, `Users`, `Company`, `PaRegistrations`, `PurchaseRequests`, `WebhookSubscriptions`. |
| `PennylaneClient::Registry` | `lib/pennylane_client/registry.rb` | Frozen lookup from operationId to Operation. An unknown id raises `UnknownOperationError`. |
| `PennylaneClient::Executor` | `lib/pennylane_client/executor.rb` | Operation + params to Request; Response to a return value or an Error. |
| `PennylaneClient::Paginator` | `lib/pennylane_client/paginator.rb` | Walks a cursor-paginated list for `client.paginate` and `client.pages`: largest page, every param but `start_date` resent on every page, lazy. |
| `PennylaneClient::Multipart`, `Upload` | `lib/pennylane_client/multipart.rb` | A multipart/form-data body that streams its files; `Upload` sets a file's filename and content type. |
| `PennylaneClient::Encoder` | `lib/pennylane_client/encoder.rb` | `BigDecimal` to `to_s("F")`, `Date`/`Time` to ISO 8601, everything else untouched. |
| `PennylaneClient::Request`, `Response` | `lib/pennylane_client/request.rb`, `response.rb` | Plain values passed to and from a Transport. `Request#inspect` filters the Authorization header. |
| `PennylaneClient::Middleware::Auth`, `Retry`, `RateLimit`, `Instrument` | `lib/pennylane_client/middleware/` | One policy each, every one `call(request) -> Response` around the next. |
| `PennylaneClient::Limiter`, `LimiterRegistry` | `lib/pennylane_client/limiter.rb`, `limiter_registry.rb` | The per-token bucket, 25 per 5 s, and the process-wide lookup that shares one per token. |
| `PennylaneClient::NetHttpTransport` | `lib/pennylane_client/net_http_transport.rb` | The default Transport, on `Net::HTTP`. |
| `PennylaneClient::Error` and subclasses | `lib/pennylane_client/errors.rb` | One class per documented status, plus `ConnectionError`, `TimeoutError`, `ExportError` and `SignatureError`. |
| `PennylaneClient::Webhook` | `lib/pennylane_client/webhook.rb` | `verify!` checks an inbound delivery's `X-Pennylane-Signature` (HMAC-SHA256 of `"{t}.{raw_body}"`, `OpenSSL.fixed_length_secure_compare`, 300 s tolerance) and returns the deep-frozen event, or raises `SignatureError`. It uses no Client. |
| `PennylaneClient::Instrumentation`, `Configuration` | `lib/pennylane_client/instrumentation.rb`, `configuration.rb` | One log line and one `on_request` event per attempt, retry and rate-limit wait. `PennylaneClient.configure` sets the defaults. |
| `SnapshotContract` (dev time, not shipped) | `tools/snapshot_contract.rb` | Builds the dated [contract snapshot](api/README.md) in `docs/api/contract/<date>/`. Run by `rake contract:snapshot`. |
| `OperationTable` (dev time, not shipped) | `tools/operation_table.rb` | Generates `operations.rb` from the latest snapshot. Run by `rake contract:sync`. |
| `Checklist` (dev time, not shipped) | `tools/checklist.rb` | Generates [`docs/api/CHECKLIST.md`](api/CHECKLIST.md). Run by `rake checklist`. |
| `Stale` (dev time, not shipped) | `tools/stale.rb` | Fails the gate when a generated file differs from its generator. Run by `rake stale`. |
| `FakePennylane`, `FakePennylane::Server` (test support, not shipped) | `test/support/fake_pennylane.rb`, `fake_pennylane/server.rb` | A Pennylane stand-in that enforces 25 per 5 s per token with the real headers, serves cursor pages and misbehaves on demand; in process as a Transport, or over HTTP on 127.0.0.1. Drives `rake load` and `rake stress` ([performance](performance.md)). |

## The request path

What happens on `client.call(:getJournal, id: 42)`:

1. **Client** hands the operationId and params to the Executor. It holds no logic of its own.
2. **Registry** turns `:getJournal` into its Operation (verb, path template, body kind). A typo raises `UnknownOperationError` before anything is sent.
3. **Executor** builds a `Request`:
   - Names in the path template (`{id}`) are taken from the params and escaped. A missing one raises `ArgumentError`, and so does one that is nil or empty (it would leave an empty segment, and `GET /customer_invoices/` is the list) or exactly `.` or `..` (a dot segment a server may resolve to another Operation).
   - If the Operation takes a JSON body, every other param goes into the body, run through the **Encoder** and `JSON.generate`. This covers `DELETE` with a body (`deleteLedgerEntryLinesUnletter`).
   - Six Operations (`putCustomerCategories` and its siblings) take a JSON array, which keywords cannot build. The caller passes the body as the second argument, `client.call(:putCustomerCategories, [...], customer_id: 9)`; keywords then fill only the path, and any left over raise `ArgumentError`. A Hash body that names a path parameter raises `ArgumentError` too.
   - Otherwise every other param goes into the query. `nil` values are left out. Hash and Array values are sent as JSON strings, because Pennylane's `filter` is a JSON array in a query string.
   - No Operation in the 2026-09-30 snapshot takes both a body and a query.
   - If the Operation takes a multipart body (the 7 uploads), every other param is a form field of a `Multipart` body. A File, IO, Pathname or `Upload` is a file part, streamed from disk; a Hash or Array is an `application/json` part; anything else is text. The body's size is known up front, so it goes with a `Content-Length`. Files the Executor opened from a Pathname are closed when the call is over.
   - Headers: `Accept: application/json`, a `User-Agent` naming the gem, and `Content-Type: application/json` (or `multipart/form-data` with its boundary) when there is a body. No token.
   - The Request also carries the `operation_id`, for events, and the `retry_policy` (`:always` when the caller passed `retry: :always`, which is never sent).
4. **Middleware** runs, outermost first. Each is `call(request) -> Response` around the next, and Client composes them:
   - **Auth** adds `Authorization: Bearer <token>`. The token is a String or a provider (`#call`), asked once per call. A token with whitespace or a line break is refused without echoing it.
   - **Retry** sends the call again when that is safe (D5): a 429 for any verb, after `retry-after`; 500, 502, 503, 504, `ConnectionError` and `TimeoutError` for GET only, or for any verb with `retry: :always`. At most 3 attempts, full-jitter backoff (a random wait up to 0.5 s, then 1 s), and at most 30 s of waiting per call (`max_retry_wait:`). A wait past the cap is not taken, so a long `retry-after` surfaces as `RateLimitError`. Each retry fires a `:retry` event. It sits outside RateLimit so every attempt takes its own call from the bucket.
   - **RateLimit** takes a call from the token's `Limiter` before each attempt and waits when the bucket is empty, firing a `:wait` event. Every response's `ratelimit-remaining` and `ratelimit-reset` correct the bucket. Limiters come from a `LimiterRegistry`, keyed by the SHA-256 of the token; `LimiterRegistry.default` is shared by every Client in the process. A limiter no one has fetched for 60 s is dropped once its window has ended and no thread waits on it, so rotating OAuth tokens or one token per company do not grow memory without bound.
   - **Instrument** records each attempt as a `:request` event, next to the Transport, so `duration` never includes a wait.
5. **Transport** sends it. Every Client shares `NetHttpTransport.default`, so building a Client per request or per token opens no new sockets; the token travels in each request, not in the connection. It keeps one keep-alive connection per host per fiber (`Thread#[]` is fiber-local), so threads and fibers never share a socket. Bodies come back tagged UTF-8; the bytes are not checked here. Timeouts are open 5 s, read 30 s, write 30 s; an upload gets 300 s to read and write, and the connection goes back to 30 s afterwards (`upload_timeout:`). An idle connection is kept for 10 s (`keep_alive_timeout:`), not `Net::HTTP`'s 2 s, because a rate-limit wait lasts up to 5 s and would otherwise cost a new connection and TLS handshake after every wait ([performance](performance.md)); `Net::HTTP` still reconnects when the server has closed the connection. A `Multipart` body is rewound, so a retry after a 429 sends the file from its first byte, and handed to `Net::HTTP` as `body_stream`, which reads it in 16 KB chunks. It sets `max_retries = 0`, because `Net::HTTP` otherwise resends an idempotent verb once on a dropped connection, and PUT and DELETE have side effects at Pennylane (D5). No response raises `TimeoutError` or `ConnectionError` and drops the connection.
6. **Instrumentation** takes every event: one log line (`info`, or `warn` for a retry or when no response came) and one frozen `on_request` event. A `:request` event has `operation_id`, `method`, `path` (no query), `status`, `error` and `duration` in ms; a `:retry` event has `attempt`, `wait`, `status` and `error`; a `:wait` event has `wait`. It never raises: a failing logger or callback is reported and ignored, so a write that reached Pennylane never looks failed to the caller.
7. **Executor** reads the final `Response`:
   - 2xx with an empty body returns `true`.
   - 2xx with a body returns `JSON.parse(..., symbolize_names: true, freeze: true)`: a deep-frozen Hash with symbol keys. A body that is not JSON, or not valid UTF-8, raises the base `Error`. A body with bad bytes is not scrubbed, because a record read with U+FFFD in place of its bytes could be written back that way.
   - Any other status raises `Error.from_response`: 400 and 422 `ValidationError`, 401 `AuthenticationError`, 403 `PermissionError`, 404 `NotFoundError`, 409 `ConflictError`, 429 `RateLimitError` (`#retry_after`), any 5xx `ServerError`, anything else the base `Error`. The message comes from the body, which Pennylane sends in three shapes (`{error, message, details}`, `{status, error}`, `{message}`) or as plain text; each is parsed defensively. A body that is not valid UTF-8 (a proxy's Latin-1 error page) is read with the bad bytes replaced, so the class still follows the status; `#body` keeps the raw bytes.

### Where the token lives

Only `Middleware::Auth` holds the token, and only `Request#headers` carries it, from Auth inward. `Client`, `Executor`, `Auth`, `Request` and `Resources::Resource` override `inspect`, errors are built from the response alone, events are built from the Operation and the URL path, and rate-limit keys are SHA-256 digests. `Request#to_h` and `#headers` do return the raw header, because a Transport needs it; a custom Transport must not log them. A token with whitespace or a line break is refused, when the Client is built or when a provider returns it, because `Net::HTTP` would otherwise raise an error quoting the header. `test/token_secrecy_test.rb` checks all of these.

### Transport interface

A Transport is anything with `call(request) -> Response` that raises `ConnectionError` or `TimeoutError` when no response arrives and never raises for an HTTP status. Pass one as `PennylaneClient.new(token:, transport:)`. `Request#body` is a String, nil, or for an upload a `Multipart`, which reads like an IO (`read`, `rewind`, `size`); rewind it before sending.

### Pagination

`client.paginate(:getCustomerInvoices, filter: [...])` builds a **Paginator** around the Executor. Each page is an ordinary call through the whole pipeline, so each page takes its own call from the rate limit and GETs retry as usual.

- It asks for the Operation's largest page (`max_limit`, 100 or 1000, read from the contract by the generator) unless the caller passed a smaller `limit`. A larger one raises `ArgumentError` before anything is sent.
- The cursor does not remember `filter` or `sort` (`guides/cursor-pagination.md`), so every param goes again on every page, next to `cursor`. The exception is `start_date`: every changelog operation answers 400 to `start_date` next to `cursor`, so it goes with the first request only.
- It stops when `has_more` is false or `next_cursor` is null.
- It returns an `Enumerator::Lazy`: reading the first ten items sends one request. Enumerating it again starts again from the first page. `client.pages` gives the page Hashes instead of the items.
- `getPaRegistrations` answers with `items`, `has_more` and `next_cursor` but takes no cursor, so an Operation that is not paginated is read as one page. A response without `items` raises `Error`; an Operation that is not a GET raises `ArgumentError`.

## Planned components

From the design diagram, in the order they are built (Epic #1):

1. **Runtime core.** Built; see above.
2. **Middleware.** Built; see above.
3. **Pagination and uploads.** Built; see above.
4. **Resources.** Hand-written one-liner methods per resource group. Customer Invoices, Customers, Supplier Invoices, Suppliers, Mandates, Transactions and bank accounts, Quotes, Commercial Documents, invoice templates and numberings, and the ledger are built; the other groups follow, one sub-issue each.

## Design rationale

The reasoning behind each choice is recorded as decisions D1 to D8 in [proposal 0001](../proposals/0001-pennylane-client-gem.md). The short version:

- **Generated table, hand-written names (D3).** Every operation is reachable from the snapshot on day one; Ruby names are chosen by a person and survive Pennylane renaming an operationId.
- **Never retry side effects (D5).** Pennylane does not enforce idempotency on creates.
- **Raw values (D6).** Money stays a string, so no field list drifts and no `bigdecimal` dependency is needed.

## Where this design would strain

Honest limits, known before the code exists:

- **Multi-process deployments share one token's budget.** The limiter is per process. Header self-correction and 429 retries absorb the overflow ([measured](performance.md): four processes, 48 calls, 3 answered 429 and all 48 succeeded); a shared store needs a limiter you inject yourself.
- **The bucket follows Pennylane's window, not a sliding one.** It refills in full when the window ends, as `ratelimit-reset` describes. Until the first response arrives, the local window may not line up with Pennylane's; the headers then move it. `ratelimit-reset` is whole seconds, so the local reset can be up to a second off (an open question in proposal 0001).
- **A write can race a server closing an idle connection.** Before reusing a connection, `Net::HTTP` checks whether the server has closed it. If the server closes it in the instant between that check and the request, a POST, PUT or DELETE fails with `ConnectionError` and is not retried, even though Pennylane never saw it. Keeping idle connections for 10 s rather than longer keeps this rare; Pennylane's own idle timeout is not documented.
- **Header correction needs a roughly correct clock.** `ratelimit-reset` is a Unix time. If the host clock is off from Pennylane's by more than about a second, a reset looks past or too far away and is ignored. `ratelimit-remaining` still drains the bucket, but the bucket keeps its own window end, which may not line up with Pennylane's. Keep NTP running.
- **D5 rests on an assumption.** A 429 is retried for writes because it should mean the request was not run. That is unconfirmed until a sandbox run (proposal 0001, open questions).
- **No live verification yet.** The maintainer has no Pennylane account, so behaviour is checked against the documentation, not a sandbox.
- **Responses are untyped.** Callers convert money and dates themselves.
