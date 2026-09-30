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
- Weekly contract drift workflow and `rake contract:drift`: any difference between Pennylane's docs and the committed snapshot opens or updates one issue labelled `drift`.

[Unreleased]: https://github.com/Davidslv/pennylane_client/commits/main
