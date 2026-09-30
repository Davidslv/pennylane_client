# Architecture

How the gem is put together, and why. Written for someone about to change the code. If the code and this document disagree, the code wins and this document has a bug.

> The gem is being built. This document describes what exists today and points to the plan for the rest. The full design is in [proposal 0001](../proposals/0001-pennylane-client-gem.md) and drawn in the [design diagram](architecture/design-diagram.md).

## What exists today

| Component | File | Role |
|---|---|---|
| `PennylaneClient` | `lib/pennylane_client.rb` | The namespace. |
| `PennylaneClient::VERSION` | `lib/pennylane_client/version.rb` | Gem version. |
| `PennylaneClient::Operation` | `lib/pennylane_client/operation.rb` | One Operation as plain data: operationId, verb, path, paginated, body kind, success code, deprecated. |
| `PennylaneClient::OPERATIONS` | `lib/pennylane_client/operations.rb` | The generated operation table: every Operation in the latest snapshot, one row per line. Every live Operation is Registered here. |
| `PennylaneClient::Client` | `lib/pennylane_client/client.rb` | Wiring only. `PennylaneClient.new(token:)` builds one; `#call(:operationId, **params)` reaches any Registered operation. |
| `PennylaneClient::Registry` | `lib/pennylane_client/registry.rb` | Frozen lookup from operationId to Operation. An unknown id raises `UnknownOperationError`. |
| `PennylaneClient::Executor` | `lib/pennylane_client/executor.rb` | Operation + params to Request; Response to a return value or an Error. |
| `PennylaneClient::Encoder` | `lib/pennylane_client/encoder.rb` | `BigDecimal` to `to_s("F")`, `Date`/`Time` to ISO 8601, everything else untouched. |
| `PennylaneClient::Request`, `Response` | `lib/pennylane_client/request.rb`, `response.rb` | Plain values passed to and from a Transport. `Request#inspect` filters the Authorization header. |
| `PennylaneClient::NetHttpTransport` | `lib/pennylane_client/net_http_transport.rb` | The default Transport, on `Net::HTTP`. |
| `PennylaneClient::Error` and subclasses | `lib/pennylane_client/errors.rb` | One class per documented status, plus `ConnectionError` and `TimeoutError`. |
| `PennylaneClient::Instrumentation`, `Configuration` | `lib/pennylane_client/instrumentation.rb`, `configuration.rb` | One log line and one `on_request` event per request. `PennylaneClient.configure` sets the defaults. |
| `SnapshotContract` (dev time, not shipped) | `tools/snapshot_contract.rb` | Builds the dated [contract snapshot](api/README.md) in `docs/api/contract/<date>/`. Run by `rake contract:snapshot`. |
| `OperationTable` (dev time, not shipped) | `tools/operation_table.rb` | Generates `operations.rb` from the latest snapshot. Run by `rake contract:sync`. |
| `Checklist` (dev time, not shipped) | `tools/checklist.rb` | Generates [`docs/api/CHECKLIST.md`](api/CHECKLIST.md). Run by `rake checklist`. |
| `Stale` (dev time, not shipped) | `tools/stale.rb` | Fails the gate when a generated file differs from its generator. Run by `rake stale`. |

## The request path

What happens on `client.call(:getJournal, id: 42)`:

1. **Client** hands the operationId and params to the Executor. It holds no logic of its own.
2. **Registry** turns `:getJournal` into its Operation (verb, path template, body kind). A typo raises `UnknownOperationError` before anything is sent.
3. **Executor** builds a `Request`:
   - Names in the path template (`{id}`) are taken from the params and escaped. A missing one raises `ArgumentError`.
   - If the Operation takes a JSON body, every other param goes into the body, run through the **Encoder** and `JSON.generate`. This covers `DELETE` with a body (`deleteLedgerEntryLinesUnletter`).
   - Otherwise every other param goes into the query. `nil` values are left out. Hash and Array values are sent as JSON strings, because Pennylane's `filter` is a JSON array in a query string.
   - No Operation in the 2026-09-30 snapshot takes both a body and a query.
   - Multipart Operations raise `NotImplementedError` until uploads land (#8).
   - Headers: `Authorization: Bearer <token>`, `Accept: application/json`, a `User-Agent` naming the gem, and `Content-Type: application/json` when there is a body.
4. **Transport** sends it. `NetHttpTransport` keeps one keep-alive connection per host per thread, so threads never share a socket. Timeouts are open 5 s, read 30 s, write 30 s. It sets `max_retries = 0`, because `Net::HTTP` otherwise resends an idempotent verb once on a dropped connection, and PUT and DELETE have side effects at Pennylane (D5). No response raises `TimeoutError` or `ConnectionError` and drops the connection.
5. **Instrumentation** records the attempt: one log line (`info`, or `warn` when no response came) and one frozen `on_request` event: `operation_id`, `method`, `path` (no query), `status`, `error`, `duration` in ms.
6. **Executor** reads the `Response`:
   - 2xx with an empty body returns `true`.
   - 2xx with a body returns `JSON.parse(..., symbolize_names: true, freeze: true)`: a deep-frozen Hash with symbol keys. A body that is not JSON raises the base `Error`.
   - Any other status raises `Error.from_response`: 400 and 422 `ValidationError`, 401 `AuthenticationError`, 403 `PermissionError`, 404 `NotFoundError`, 409 `ConflictError`, 429 `RateLimitError` (`#retry_after`), any 5xx `ServerError`, anything else the base `Error`. The message comes from the body, which Pennylane sends in three shapes (`{error, message, details}`, `{status, error}`, `{message}`) or as plain text; each is parsed defensively.

### Where the token lives

Only the Executor holds the token, and only `Request#headers` carries it. `Client`, `Executor` and `Request` override `inspect`, errors are built from the response alone, and events are built from the Operation and the URL path. `test/token_secrecy_test.rb` checks all of these.

### Transport interface

A Transport is anything with `call(request) -> Response` that raises `ConnectionError` or `TimeoutError` when no response arrives and never raises for an HTTP status. Pass one as `PennylaneClient.new(token:, transport:)`.

## Planned components

From the design diagram, in the order they are built (Epic #1):

1. **Runtime core.** Built; see above.
2. **Middleware.** `Auth` (token provider), `RateLimit` (25 requests per 5 seconds per token), `Retry` (429 for any method, 5xx for GET only).
3. **Pagination and uploads.** Cursor pagination that re-sends filters on every page; multipart uploads.
4. **Resources.** Hand-written one-liner methods per resource group.

## Design rationale

The reasoning behind each choice is recorded as decisions D1 to D8 in [proposal 0001](../proposals/0001-pennylane-client-gem.md). The short version:

- **Generated table, hand-written names (D3).** Every operation is reachable from the snapshot on day one; Ruby names are chosen by a person and survive Pennylane renaming an operationId.
- **Never retry side effects (D5).** Pennylane does not enforce idempotency on creates.
- **Raw values (D6).** Money stays a string, so no field list drifts and no `bigdecimal` dependency is needed.

## Where this design would strain

Honest limits, known before the code exists:

- **Multi-process deployments share one token's budget.** The limiter is per process. Header self-correction and 429 retries absorb the overflow; a shared store needs a limiter you inject yourself.
- **No live verification yet.** The maintainer has no Pennylane account, so behaviour is checked against the documentation, not a sandbox.
- **Responses are untyped.** Callers convert money and dates themselves.
