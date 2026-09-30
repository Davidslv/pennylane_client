# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- A call cut short by an exception the transport does not rescue (`Timeout.timeout`, rack-timeout, `Interrupt`) now drops its connection. Before, the unread answer stayed on the kept-alive socket and was returned to the next call on that thread, which could be for another token.

## [0.1.0] - 2026-09-30

First release. Every live operation is reachable through `client.call` and has a named method.

### Added

- Gem skeleton: `PennylaneClient` module, gemspec with zero runtime dependencies, Ruby 3.3+.
- Repository standards: community health files, issue forms, CI on Ruby 3.3, 3.4 and 4.0, RuboCop, RBS validation, bundler-audit.
- Contract snapshot of the Company API v2 (2026-09-30) and `rake contract:snapshot`.
- `PennylaneClient::Operation` and the generated operation table `PennylaneClient::OPERATIONS` (`rake contract:sync`): all 178 operations Registered, 177 live.
- Generated `docs/api/CHECKLIST.md` (`rake checklist`) and `rake stale`, which fails the gate when either generated file is out of date.
- `PennylaneClient.new(token:)` and `client.call(:operationId, **params)`: every Registered operation is callable. Responses are deep-frozen Hashes with symbol keys; an empty 2xx returns `true`.
- Error classes under `PennylaneClient::Error`, one per documented status, plus `ConnectionError` and `TimeoutError`.
- Request encoding of `BigDecimal`, `Date` and `Time`; `NetHttpTransport` with keep-alive and 5/30/30 s timeouts.
- `PennylaneClient.configure` with `logger` and `on_request`. The token never appears in logs, `inspect`, errors or events.
- Middleware pipeline around the Transport: `Auth`, `Retry`, `RateLimit`, `Instrument`.
- `token:` also accepts a token provider, anything responding to `#call`, asked once per call.
- Client-side rate limiting: a token bucket of 25 requests per 5 seconds per token, shared across clients and threads through `LimiterRegistry.default`, corrected by Pennylane's `ratelimit-remaining` and `ratelimit-reset` headers. Pass `limiters:` to bring your own.
- Retries: 429 for any verb after `retry-after`; 500, 502, 503, 504 and no response for GET only. At most 3 attempts, full jitter, 30 s of waiting per call (`max_retry_wait:`). `client.call(..., retry: :always)` opts a write in.
- Events now carry `type:` (`:request`, `:retry` or `:wait`); every attempt, retry and rate-limit wait fires one.
- Weekly contract drift workflow and `rake contract:drift`: any difference between Pennylane's docs and the committed snapshot opens or updates one issue labelled `drift`.
- Cursor pagination: `client.paginate(:operationId, **params)` returns every item as an `Enumerator::Lazy`, following `next_cursor` and resending `filter` and `sort` on every page, at the operation's largest page size. `client.pages` gives the pages. `Operation#max_limit` records the largest page size.
- Multipart uploads for the 7 upload operations: pass a `File`, IO, `Pathname` or `PennylaneClient::Upload`. Files stream from disk; uploads get 300 s timeouts (`upload_timeout:`).
- `FakePennylane`, a test-support stand-in that enforces Pennylane's rate limit and headers and misbehaves on demand, in process or on a local socket. `rake load` and `rake stress` run the client against it; results in `docs/performance.md`. CI runs `rake load` on every pull request and `rake stress` on demand.
- `NetHttpTransport` keeps an idle connection for 10 s (`keep_alive_timeout:`) instead of `Net::HTTP`'s 2 s, so a rate-limit wait no longer costs a new connection.
- `client.customer_invoices`: all 24 Customer Invoices operations Named, including the Hidden installment action. `list` and the lists under one invoice walk every page; `import_e_invoice` and `upload_appendix` stream their file; `categorize` takes the bare array. RBS in `sig/pennylane_client/resources.rbs`.
- `client.customers`: all 16 Customers operations Named, company and individual, with contacts and categories. `create_company` and `create_individual` are the documented creates; `create(customer_type:, ...)` is the Hidden one that makes either kind.
- `client.supplier_invoices` and `client.suppliers`: all 20 Supplier Invoices and Suppliers operations Named. Supplier invoices come in by `import` or `import_e_invoice`; importing a file twice raises `ConflictError`. `validate_accounting`, `update_payment_status(id, payment_status:)` and `update_e_invoice_status(id, status:, reason:)` cover the lifecycle.
- `client.sepa_mandates`, `client.gocardless_mandates` and `client.pro_account_mandates`: all 14 Mandates operations Named. GoCardless mandates add `send_request`, `associate` and `cancel`; Pro Account mandates add `send_request`, `migration_candidates` and `migrate`. Pro Account operations raise `NotFoundError` without a Pro Account and `PermissionError` without an enabled merchant profile.
- `client.bank_accounts`, `client.bank_establishments` and `client.transactions`: all 15 Transactions and bank operations Named. Transactions have `categories`, `categorize` (bare array) and `matched_invoices`; `update` sets the third party, `customer_id:` or `supplier_id:`. `match_transaction(id, transaction_id:)` and `unmatch_transaction(id, transaction_id)` on both invoice resources match a transaction to an invoice.
- `client.quotes`, `client.commercial_documents`, `client.customer_invoice_templates` and `client.numberings`: all 20 Quotes, Commercial Documents, invoice template and numbering operations Named. Quotes add `send_by_email` and `update_status(id, status:)`; both document resources list `invoice_lines`, `invoice_line_sections` and `appendices` and stream `upload_appendix`. `client.numberings.list` shows which document types Pennylane can number.
- `client.journals`, `client.ledger_accounts`, `client.ledger_entries`, `client.ledger_entry_lines`, `client.fiscal_years`, `client.trial_balance` and `client.file_attachments`: all 22 live ledger operations Named. Ledger entry lines add `letter` and `unletter` (both require `unbalanced_lettering_strategy:`), `lettered_lines`, `categories` and `categorize`. `trial_balance.list(period_start:, period_end:)` walks 1000 accounts a page. `file_attachments.upload` replaces the deprecated `postLedgerAttachments`, which has no named method.
- `client.categories`, `client.category_groups` and `client.products`: all 13 Categories, Category Groups and Products operations Named. `category_groups.categories(id)` lists the categories in one group.
- `client.changelogs` and `client.exports`: all 16 Changelogs and Exports operations Named, `getQuoteChanges` included. Each changelog method takes `since:` for the `start_date`. `exports.generate_fec`, `generate_general_ledger` and `generate_analytical_general_ledger` create the export and poll it until ready, raising the new `ExportError` when it fails or times out.
- `client.billing_subscriptions`, `client.purchase_requests`, `client.webhook_subscriptions`, `client.users.me`, `client.company.features` and `client.pa_registrations.list`: the last 17 live operations Named, so all 177 are. `pa_registrations.list` returns the items of its one response, since Pennylane takes no cursor there.
- `client.paginate` sends `start_date` with the first page only. Pennylane answers 400 to `start_date` next to a `cursor`, so a changelog walk failed on its second page.
- `rake smoke`, for contributors with a Pennylane sandbox: paced reads of every parameter-free list and its first item, opt-in writes that clean up after themselves, and opt-in checks of the 429-on-a-write assumption and of a captured webhook delivery. It writes a report to `docs/api/live/`; without `PENNYLANE_SMOKE_TOKEN` it skips and exits 0. Not part of the gate.
- `rake checklist` reads the sandbox reports into the checklist's `live` column and a "Sandbox checks" table, and writes the live-verified count into `README.md`. `rake stale` covers that count.
- `PennylaneClient::Webhook.verify!(raw_body, signature, secret:)`: checks an inbound webhook's HMAC-SHA256 signature in constant time and its timestamp within 300 s (`tolerance:`), and returns the deep-frozen event. A bad delivery raises `PennylaneClient::SignatureError`.
- Release workflow: a `v*` tag runs the gate and publishes to RubyGems by Trusted Publishing, with a Sigstore attestation. See `docs/releasing.md`.
- The gate checks the README's operation counts against `docs/api/CHECKLIST.md`.

[Unreleased]: https://github.com/Davidslv/pennylane_client/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Davidslv/pennylane_client/releases/tag/v0.1.0
