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
- Weekly contract drift workflow and `rake contract:drift`: any difference between Pennylane's docs and the committed snapshot opens or updates one issue labelled `drift`.

[Unreleased]: https://github.com/Davidslv/pennylane_client/commits/main
