# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) for the public API listed in the README's [Public API](README.md#public-api) section; everything else is `@api private` and may change in any release. Before 1.0.0, a minor release may change the public API. From 1.0.0, only the Experimental methods listed under [Stability](README.md#stability) may change in a minor release.

## [Unreleased]

## [0.1.0] - 2026-09-30

First release. All 178 operations of the Company API v2 (contract snapshot of 2026-09-30) are reachable through `client.call`, and each of the 177 live ones has a named method. Zero runtime dependencies; Ruby 3.3 or newer.

### Added

#### Calling Pennylane

- `PennylaneClient.new(token:)` and `client.call(:operationId, **params)` for any Registered operation. Keywords fill the path, then the JSON body or the query; a body that is a JSON array is passed positionally. Responses are deep-frozen Hashes with symbol keys, as Pennylane sends them, and an empty 2xx returns `true`. Money stays a decimal String.
- `token:` takes a String or a token provider (anything responding to `#call`), asked once per call. The client never refreshes a token.
- Request encoding: `BigDecimal` to a plain decimal String, `Date` to ISO 8601, `Time` and `DateTime` to ISO 8601 with microseconds when they have a fraction of a second.
- Path parameters are escaped. A missing, nil or empty one, or `.` or `..`, raises `ArgumentError` before anything is sent.
- Errors under `PennylaneClient::Error` (`status`, `code`, `details`, `body`, `headers`): `ValidationError` (400, 422), `AuthenticationError` (401), `PermissionError` (403), `NotFoundError` (404), `ConflictError` (409), `RateLimitError` (429, `#retry_after`), `ServerError` (5xx), `ConnectionError` and `TimeoutError`. An unknown operationId raises `UnknownOperationError`, an `ArgumentError`.
- Cursor pagination: `client.paginate(:operationId, **params)` returns every item as an `Enumerator::Lazy` at the operation's largest page size, resending `filter` and `sort` on every page and sending `start_date` with the first page only. `client.pages` gives the pages.
- Multipart uploads for the 7 upload operations: pass a `File`, IO, `Pathname` or `PennylaneClient::Upload` (to set the filename or content type). Files stream from disk. An IO is read from its position when the call starts, and a retry after a 429 sends the same bytes again.

#### Rate limit, retries and transport

- Client-side rate limiting: a token bucket of 25 requests per 5 s per token, shared across clients and threads through `LimiterRegistry.default`, corrected by Pennylane's `ratelimit-remaining` and `ratelimit-reset` headers. A reset that disagrees with the host clock is ignored; the remaining count still applies. Limiters for tokens not used for 60 s are dropped (`LimiterRegistry.new(idle_after:)`). Pass `limiters:` to bring your own limiter.
- Retries: a 429 for any verb, after `retry-after`; 500, 502, 503, 504 and no response for GET only. At most 3 attempts, full jitter, and at most 30 s of waiting per call (`max_retry_wait:`). `retry: :always` opts a write in, on `client.call` and on every named write.
- `NetHttpTransport`, on `Net::HTTP`: one keep-alive connection per host per thread or fiber, shared by every Client; timeouts of 5 s open, 30 s read and write, 300 s for uploads; idle connections kept 10 s (`keep_alive_timeout:`); `Net::HTTP`'s own retry turned off. A call that does not complete drops its connection, and the connections of finished threads and fibers are closed.
- Instrumentation: `PennylaneClient.configure` with `logger` and `on_request`. Every attempt, retry and rate-limit wait emits one log line and one frozen event (`type:` `:request`, `:retry` or `:wait`). A failing logger or callback never fails the call. The token never appears in logs, `inspect`, errors or events.

#### Named methods

Every live operation has a hand-written Ruby name. Lists return an `Enumerator::Lazy` that walks every page. Every named write takes `retry:`.

- `client.customer_invoices`: all 24 Customer Invoices operations, including `finalize`, `send_by_email`, `import_e_invoice`, `upload_appendix`, `categorize` (a bare array), `match_transaction(id, transaction_id:)` and `unmatch_transaction(id, transaction_id:)`.
- `client.customers`: all 16 Customers operations, company and individual, with contacts and categories. `create_company` and `create_individual` are the documented creates.
- `client.supplier_invoices` and `client.suppliers`: all 20 operations. Supplier invoices come in by `import` or `import_e_invoice`; `validate_accounting`, `update_payment_status(id, payment_status:)`, `update_e_invoice_status(id, status:)`, `match_transaction` and `unmatch_transaction` cover the lifecycle.
- `client.sepa_mandates`, `client.gocardless_mandates` and `client.pro_account_mandates`: all 14 Mandates operations.
- `client.bank_accounts`, `client.bank_establishments` and `client.transactions`: all 15 Transactions and bank operations.
- `client.quotes`, `client.commercial_documents`, `client.customer_invoice_templates` and `client.numberings`: all 20 operations.
- `client.journals`, `client.ledger_accounts`, `client.ledger_entries`, `client.ledger_entry_lines`, `client.fiscal_years`, `client.trial_balance` and `client.file_attachments`: all 22 live ledger operations, lettering included. The deprecated `postLedgerAttachments` has no named method; `file_attachments.upload` replaces it.
- `client.categories`, `client.category_groups` and `client.products`: all 13 operations.
- `client.changelogs`: one feed per record type, all 10. Each takes `since:`, a Time, a DateTime or an RFC 3339 String; anything else, a Date included, raises `ArgumentError`, and so does `start_date:`.
- `client.exports`: the FEC, General Ledger and Analytical General Ledger. `generate_*` creates the export and polls it until ready, raising `ExportError` when it fails or times out.
- `client.billing_subscriptions`, `client.purchase_requests`, `client.webhook_subscriptions`, `client.users.me`, `client.company.features` and `client.pa_registrations.list`. `pa_registrations.list` returns an `Enumerator::Lazy` like every other list, and raises `Error` if Pennylane ever answers `has_more: true` there, since that operation takes no cursor.
- A keyword that names a positional path parameter raises `ArgumentError`, so `update(1, id: 2)` cannot write record 2.

#### Webhooks

- `PennylaneClient::Webhook.verify!(raw_body, signature, secret:)` checks an inbound delivery's HMAC-SHA256 signature in constant time and its timestamp within 300 s (`tolerance:`), and returns the deep-frozen event. A bad delivery raises `PennylaneClient::SignatureError`.

#### Stability

- A declared public API: the README's Public API section lists what SemVer covers. Everything else is tagged `@api private`.
- An Experimental tier for methods that wrap an operation or input Pennylane marks Hidden, alpha or beta: `customers.create`, `customer_invoices.mark_installment_as_paid`, every `webhook_subscriptions` method, and the UBL and CII XML input of both `import_e_invoice` methods. They are listed in the README under Stability and may change in a minor release.

#### Project

- Contract snapshot of the Company API v2 (2026-09-30), the generated operation table (`rake contract:sync`), `docs/api/CHECKLIST.md` (`rake checklist`) and `rake stale`, which fails the gate when a generated file is out of date.
- A weekly contract drift workflow and `rake contract:drift`: a difference between Pennylane's docs and the snapshot opens or updates one issue labelled `drift`.
- `FakePennylane`, a test-support stand-in that enforces Pennylane's rate limit and misbehaves on demand. `rake load` and `rake stress` run the client against it; results in `docs/performance.md`.
- `rake smoke`, for contributors with a Pennylane sandbox: paced reads, opt-in writes that clean up after themselves, and opt-in checks of the 429-on-a-write assumption and of a captured webhook delivery. Reports in `docs/api/live/` feed the checklist's `live` column and the README's live-verified count.
- Gate checks that `sig/` matches the code, that each `# names:` marker's test sends its operation, that the Public API and Experimental lists match the code, and that the README's counts match the checklist.
- Release workflow: a `v*` tag runs the gate and publishes to RubyGems by Trusted Publishing, with a Sigstore attestation. See `docs/releasing.md`.

### Pre-release review

An independent review before the first release found problems in the unreleased code. None of them reached a published version. The review fixed:

- A call cut short by an exception the transport does not rescue (`Timeout.timeout`, rack-timeout, `Interrupt`) left its answer on the kept-alive socket, to be returned to the next call on that thread, possibly for another token. Such a call now drops its connection.
- A nil, empty, `.` or `..` path parameter could send a request to another operation (`find(nil)` read the list). It now raises `ArgumentError`.
- A keyword naming a positional id replaced it (`update(1, id: 2)` wrote record 2). It now raises `ArgumentError`, and so does a `client.call` Hash body that names a path parameter.
- A response body that was not valid UTF-8 raised `Encoding::CompatibilityError` and lost the error class. Error bodies are now read with the bad bytes replaced; a 2xx body raises `Error`.
- `LimiterRegistry.default` grew by one limiter per token forever. Idle limiters are now dropped.
- A `ratelimit-reset` that disagreed with the host clock also discarded `ratelimit-remaining`. The count now applies either way.
- Connections of finished threads stayed open until GC. They are now closed when another connection opens.
- `since:` given a Time dropped its microseconds, so a resumed changelog started early. They are now sent.
- Public API settled before release: `retry:` on every named write, `pa_registrations.list` lazy like every other list, `unmatch_transaction(id, transaction_id:)` matching `match_transaction`, changelogs refusing `start_date:`, the Experimental tier and the declared public API.
- The gate now catches drift between `sig/` and the code, `# names:` markers whose test sends nothing, and a success range wider than 2xx.

[Unreleased]: https://github.com/Davidslv/pennylane_client/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Davidslv/pennylane_client/releases/tag/v0.1.0
