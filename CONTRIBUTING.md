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

1. the Minitest suite (`test/`), which stubs all HTTP with WebMock and never reaches Pennylane. It includes `test/signatures_test.rb`, which fails when `sig/` drifts from the code: a method with no signature, a public method whose signature takes other parameters, or an instance variable that is not declared;
2. RuboCop;
3. `rbs validate` on `sig/`;
4. `rake stale`, which fails if `lib/pennylane_client/operations.rb`, `docs/api/CHECKLIST.md` or the live-verified count in `README.md` differs from what its generator writes.

The repository does not commit a `Gemfile.lock`, as recommended for gems.

`bundle exec rake contract:snapshot` takes a new [contract snapshot](docs/api/README.md) from Pennylane's docs site. `bundle exec rake contract:drift` prints how the docs differ from the latest snapshot; a weekly workflow runs the same check and opens a `drift` issue. Neither is part of the gate. With `rake smoke` (below), they are the only tasks that reach the network.

`bundle exec rake load` (about 25 s) and `bundle exec rake stress` (about 40 s; `rake "stress[30]"` adds a 30-minute soak) run the client against `FakePennylane` on 127.0.0.1 and fail on a 429 under steady load, an unbounded retry, a write sent twice, a wrong error class, a deadlock or a leaked thread or socket. CI runs `rake load` on every pull request; the Stress workflow runs `rake stress` on demand. Run them after changing the middleware or the transport. Results and how to read them are in [docs/performance.md](docs/performance.md).

`bundle exec rake contract:sync checklist` regenerates the operation table, the checklist and the README's live-verified count. Run it after a new snapshot, after adding a behaviour test that names an operation, and after adding a sandbox report. Commit what it writes; never edit either file by hand.

### Naming an operation

A behaviour test names an Operation with a marker comment directly above the test method, one operationId per line:

```ruby
# names: finalizeCustomerInvoice
def test_finalize
```

Only tests under `test/resources/` are read. The marker must name an operationId in the snapshot and sit directly above a `def test_` line (other comments in between are fine), or `rake checklist` fails. The test must also send that Operation: the suite records the operationId of every request that reaches the transport during a test under `test/resources/`, and fails a passing test that did not send an Operation its markers name (`test/support/named_trace.rb`).

## What every change needs

- **A test first.** Write the failing test, then the code. A change without a test is not done.
- **Stubbed HTTP only.** New HTTP interactions get WebMock stubs, never live calls.
- **RBS for every method.** Every method in `lib/` gets a signature in `sig/` and every instance variable is declared; `test/signatures_test.rb` checks it.
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

The maintainer has no Pennylane account. The [checklist](docs/api/CHECKLIST.md) records per operation, in its `live` column, whether a contributor has verified it against a sandbox, and the README states the count. If you have a Pennylane company account with a sandbox, one run of `rake smoke` moves operations from `unverified` to `sandbox-verified <date> (by @you)`.

Use a developer token for a **sandbox** company, never production. Then:

```sh
PENNYLANE_SMOKE_TOKEN=... PENNYLANE_SMOKE_GITHUB_USER=your-github-name bundle exec rake smoke
```

This sends reads only: every live list operation that needs no parameters, one item each, then the detail read of the first item each list returns. It waits 0.5 s before every request, so it never gets near the rate limit. A 403 means the token lacks that scope and is recorded as `not run`, not as a failure.

Optional, each off unless you set it:

- `PENNYLANE_SMOKE_SANDBOX=yes` confirms the token is for a sandbox and turns on writes. The run creates, reads, updates and deletes a contact on your first customer, and, if the company has no webhook subscription, a disabled one pointing at `https://example.com`. Everything it creates is deleted, even when a step fails. An existing webhook subscription is never touched.
- `PENNYLANE_SMOKE_PROBE_429=yes` (with `PENNYLANE_SMOKE_SANDBOX=yes`) checks the assumption behind [D5](proposals/0001-pennylane-client-gem.md) that Pennylane does not run a request it answers with 429. It sends up to 30 quick `getMe` calls until one is rate-limited, sends one contact create into the exhausted window, waits out `retry-after`, and looks for the contact. The probe client never retries, so each request goes out once. This is the only time the run reaches the rate limit: one burst, on purpose. If Pennylane is slow to list a new contact, the check can pass falsely; run it twice if it matters.
- `PENNYLANE_SMOKE_WEBHOOK_BODY` (a file holding the raw body), `PENNYLANE_SMOKE_WEBHOOK_SIGNATURE` (the `X-Pennylane-Signature` header) and `PENNYLANE_SMOKE_WEBHOOK_SECRET` check a delivery you captured from your sandbox against `Webhook.verify!`.

The run writes `docs/api/live/<date>-<your-github-name>.json`. It holds operationIds, results and HTTP statuses only: no ids, no response bodies, no token. Error messages are printed to your terminal, not written to the report. Read the file, then:

```sh
bundle exec rake checklist
```

and open a pull request with the report, `docs/api/CHECKLIST.md` and `README.md`. For each operation the latest report that ran it decides its `live` cell, so a later failure clears an earlier pass. A `not run` (a missing scope) leaves an earlier pass alone. If a cleanup delete fails, the run prints what to delete by hand.

`rake smoke` is never part of `bundle exec rake` and never runs in CI. Never run load or stress tests against Pennylane's servers, sandbox included.

## Code of conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
