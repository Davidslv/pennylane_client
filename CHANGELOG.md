# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/Davidslv/pennylane_client/commits/main
