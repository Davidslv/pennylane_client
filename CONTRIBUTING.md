# Contributing to pennylane_client

Thanks for your interest. This document covers setup, what a change must include, and how larger work is proposed.

## Development setup

```sh
git clone https://github.com/Davidslv/pennylane_client.git
cd pennylane_client
bundle install
bundle exec rake
```

You need Ruby 3.3 or newer and a recent Bundler (4.x recommended). The Gemfile uses `lockfile false`, which Bundler 2.5, the default on Ruby 3.3, rejects: run `gem install bundler` first. CI runs on Ruby 3.3, 3.4 and 4.0.

`bundle exec rake` is the gate. It runs:

1. the Minitest suite (`test/`), which stubs all HTTP with WebMock and never reaches Pennylane;
2. RuboCop;
3. `rbs validate` on `sig/`;
4. `rake stale`, which fails if `lib/pennylane_client/operations.rb` or `docs/api/CHECKLIST.md` differs from what its generator writes.

The repository does not commit a `Gemfile.lock`, as recommended for gems.

`bundle exec rake contract:snapshot` takes a new [contract snapshot](docs/api/README.md) from Pennylane's docs site. `bundle exec rake contract:drift` prints how the docs differ from the latest snapshot; a weekly workflow runs the same check and opens a `drift` issue. Neither is part of the gate, and they are the only tasks that reach the network.

`bundle exec rake load` (about 25 s) and `bundle exec rake stress` (about 40 s; `rake "stress[30]"` adds a 30-minute soak) run the client against `FakePennylane` on 127.0.0.1 and fail on a 429 under steady load, an unbounded retry, a write sent twice, a wrong error class, a deadlock or a leaked thread or socket. CI runs `rake load` on every pull request; the Stress workflow runs `rake stress` on demand. Run them after changing the middleware or the transport. Results and how to read them are in [docs/performance.md](docs/performance.md).

`bundle exec rake contract:sync checklist` regenerates the operation table and the checklist. Run it after a new snapshot and after adding a behaviour test that names an operation. Commit what it writes; never edit either file by hand.

### Naming an operation

A behaviour test names an Operation with a marker comment directly above the test method, one operationId per line:

```ruby
# names: finalizeCustomerInvoice
def test_finalize
```

Only tests under `test/resources/` are read. The marker must name an operationId in the snapshot and sit directly above a `def test_` line (other comments in between are fine), or `rake checklist` fails.

## What every change needs

- **A test first.** Write the failing test, then the code. A change without a test is not done.
- **Stubbed HTTP only.** New HTTP interactions get WebMock stubs, never live calls.
- **RBS for public methods.** Anything public gets a signature in `sig/`.
- **Docs in the same change.** If public behaviour changes, update `README.md` and `docs/`. If internals change in a way that invalidates `docs/architecture.md`, fix it too.

## The clean-room rule

This gem is written only from Pennylane's public documentation and observed sandbox behaviour. Do not read, copy or adapt the source, README or tests of any other Pennylane API client, in any language. If the docs are unclear, open an issue describing the ambiguity. See [CONTEXT.md](CONTEXT.md).

## Zero runtime dependencies

The gem uses only the Ruby standard library. Pull requests that add a runtime dependency will be declined unless there is no reasonable alternative.

## Commits and pull requests

- One concern per commit. Imperative subject ("Add cursor pagination"); the body explains why.
- Branch `<issue-number>-kebab-description`, PR title `[#<issue-number>] Description`.
- Pull requests describe the problem, the approach and how it was tested.

## Proposing larger changes

Open an issue first for features, API changes or behaviour changes. Significant design lives in `proposals/`.

## Verifying against a real Pennylane sandbox

The maintainer has no Pennylane account, so no operation has been verified against a live sandbox. The [checklist](docs/api/CHECKLIST.md) records this per operation in its `live` column. If you have a Pennylane company account with a sandbox, you can help by running the smoke suite once it exists (tracked in the Epic) and submitting the report. Never run load or stress tests against Pennylane's servers, sandbox included.

## Code of conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
