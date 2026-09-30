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

`bundle exec rake` is the gate. CI runs it on every pull request on Ruby 3.3, 3.4 and 4.0. It runs:

1. **The Minitest suite** (`test/`). All HTTP is stubbed with WebMock, and `test/network_guard_test.rb` checks that a real request is refused. Besides the behaviour tests, the suite holds the checks that keep code, signatures and docs in step:
   - `test/signatures_test.rb`: `sig/` matches `lib/`. It fails on a method with no signature, a public method whose signature takes other parameters than the code, or an instance variable that is not declared.
   - `test/support/named_trace.rb`: a test under `test/resources/` must send every Operation its `# names:` markers name, or it fails. See [Naming an operation](#naming-an-operation).
   - `test/public_api_test.rb`: every constant under `PennylaneClient` is either listed in the README's Public API section or tagged `@api private` where it is defined, never both.
   - `test/stability_test.rb`: the README's Experimental list equals the methods marked `@note Experimental:` in `lib/`.
   - `test/named_write_retry_test.rb`: every named write takes `retry:`, and the number of named writes is pinned.
   - `test/readme_test.rb` and `test/gemspec_test.rb`: the README's operation counts match the checklist, `CHANGELOG.md` has a dated entry for `VERSION`, and the gem ships no runtime dependency.
   - `test/token_secrecy_test.rb`: the token never shows in `inspect`, errors or events.
   - Tests that run the Ruby examples in the docs, where a doc has them: an example that no longer matches the API fails the gate.
2. **RuboCop.**
3. **`rbs validate`** on `sig/`. It checks that the signatures are well formed; `test/signatures_test.rb` checks that they match the code.
4. **`rake stale`.** It fails if `lib/pennylane_client/operations.rb`, `docs/api/CHECKLIST.md` or the live-verified count in `README.md` differs from what its generator writes.

The repository does not commit a `Gemfile.lock`, as recommended for gems.

`bundle exec rake contract:snapshot` takes a new [contract snapshot](docs/api/README.md) from Pennylane's docs site. `bundle exec rake contract:drift` prints how the docs differ from the latest snapshot. Neither is part of the gate. With `rake smoke` (below), they are the only tasks that reach the network.

`bundle exec rake load` (about 25 s) and `bundle exec rake stress` (about 40 s; `rake "stress[30]"` adds a 30-minute soak) run the client against `FakePennylane` on 127.0.0.1 and fail on a 429 under steady load, an unbounded retry, a write sent twice, a wrong error class, a deadlock or a leaked thread or socket. CI runs `rake load` on every pull request; the Stress workflow runs `rake stress` on demand. Run them after changing the middleware or the transport, and update [docs/performance.md](docs/performance.md) from the results block they print.

`bundle exec rake contract:sync checklist` regenerates the operation table, the checklist and the README's live-verified count. Run it after a new snapshot, after adding or renaming a behaviour test that names an operation, and after adding a sandbox report. Commit what it writes; never edit those files by hand.

### Naming an operation

A behaviour test names an Operation with a marker comment directly above the test method, one operationId per line:

```ruby
# names: finalizeCustomerInvoice
def test_finalize
```

Only tests under `test/resources/` are read. The marker must name an operationId in the snapshot and sit directly above a `def test_` line (other comments in between are fine), or `rake checklist` fails. The test must also send that Operation: the suite records the operationId of every request that reaches the transport during a test under `test/resources/`, and fails a passing test that did not send an Operation its markers name.

### Adding a named method

1. Write the failing behaviour test in `test/resources/<group>_test.rb`, with the `# names:` marker. Write the expected path and body by hand from the docs in the snapshot, and use realistic data from the snapshot's examples.
2. Add the method to the resource class in `lib/pennylane_client/resources/`, as a one-liner over `call`, `paginate`, `call_on` or `paginate_on`. Follow the argument rule in [AGENTS.md](AGENTS.md#conventions): ids positional, creates and updates take `**attributes`, actions take their required fields as keywords, and every write takes `retry: nil`. A write also raises the pinned count in `test/named_write_retry_test.rb`.
3. Add its signature to `sig/pennylane_client/resources.rbs`.
4. If Pennylane marks the Operation or an input Hidden, alpha or beta, add `@note Experimental:` to the method's comment and list it under Stability in `README.md`.
5. Run `bundle exec rake contract:sync checklist` and commit the regenerated checklist.
6. Add a line to `CHANGELOG.md` under `[Unreleased]`.

### Renaming a named method

A named method's Ruby name is a promise to callers (D3).

- **Pennylane renames an operationId.** Keep the Ruby name. Change the operationId in the one-liner and in the `# names:` marker, then run `rake contract:sync checklist`.
- **The gem renames a method.** Before 1.0 this is allowed: change the method, its signature, its test, the docs and the README lists that name it, and record it in the changelog. From 1.0 it is a breaking change for any method not marked Experimental: add the new method, keep the old one as a one-liner that calls it, mark the old one `@deprecated`, and remove it only in the next major version. An Experimental method may be renamed in a minor release.

### Handling a drift issue

The weekly [contract drift workflow](docs/api/README.md#drift) opens one issue labelled `drift`, or updates the one already open, when Pennylane's docs differ from the latest snapshot. It never commits. To resolve one:

1. Read the issue, or run `bundle exec rake contract:drift` for the same report.
2. On a branch, run `bundle exec rake contract:snapshot`. It writes a new dated folder under `docs/api/contract/`; older ones are kept.
3. Run `bundle exec rake contract:sync checklist`. New operations are now Registered and reachable through `client.call`.
4. Change the code to match: name new operations (above), update methods whose parameters or fields changed, and deprecate or remove what Pennylane removed. Update the README's operation counts; `test/readme_test.rb` fails until they match the checklist.
5. Open one pull request with the snapshot and the matching code, and close the drift issue from it.

## What every change needs

- **A test first.** Write the failing test, then the code. A change without a test is not done.
- **Stubbed HTTP only.** New HTTP interactions get WebMock stubs, never live calls.
- **RBS for every method.** Every method in `lib/` gets a signature in `sig/` and every instance variable is declared; `test/signatures_test.rb` checks it.
- **A place for every new constant.** List it in the README's Public API section, or tag it `@api private` where it is defined.
- **Docs in the same change.** If public behaviour changes, update `README.md` and `docs/`. If internals change in a way that invalidates `docs/architecture.md` or the [design diagram](docs/architecture/design-diagram.md), fix them too.
- **A changelog line** under `[Unreleased]` for anything a user would notice.

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
