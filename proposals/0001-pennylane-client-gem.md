# Proposal 0001: pennylane_client, a Ruby client for the Pennylane Company API v2

**Status:** Accepted
**Created:** 2026-09-30
**Project:** pennylane_client
**Author:** David Silva
**Epic:** https://github.com/Davidslv/pennylane_client/issues/1
**Sub-issues:**
- https://github.com/Davidslv/pennylane_client/issues/2 — Scaffold the gem and ship the notes#117 repository layers
- https://github.com/Davidslv/pennylane_client/issues/3 — Build the contract snapshot tool and commit the first snapshot
- https://github.com/Davidslv/pennylane_client/issues/4 — Generate the operation table and CHECKLIST.md with a CI stale gate
- https://github.com/Davidslv/pennylane_client/issues/5 — Add the weekly contract drift workflow
- https://github.com/Davidslv/pennylane_client/issues/6 — Build Operation, Registry, Executor, errors, encoder and transport; add client.call
- https://github.com/Davidslv/pennylane_client/issues/7 — Add the middleware pipeline: Auth, RateLimit, Retry
- https://github.com/Davidslv/pennylane_client/issues/8 — Add cursor pagination and multipart uploads
- https://github.com/Davidslv/pennylane_client/issues/9 — Build FakePennylane with rake load and rake stress
- https://github.com/Davidslv/pennylane_client/issues/10 — Name the Customer Invoices operations
- https://github.com/Davidslv/pennylane_client/issues/11 — Name the Customers operations
- https://github.com/Davidslv/pennylane_client/issues/12 — Name the Supplier Invoices and Suppliers operations
- https://github.com/Davidslv/pennylane_client/issues/13 — Name the Mandates operations
- https://github.com/Davidslv/pennylane_client/issues/14 — Name the Transactions and bank operations
- https://github.com/Davidslv/pennylane_client/issues/15 — Name the Quotes, Commercial Documents and numbering operations
- https://github.com/Davidslv/pennylane_client/issues/16 — Name the ledger operations
- https://github.com/Davidslv/pennylane_client/issues/17 — Name the Categories, Category Groups and Products operations
- https://github.com/Davidslv/pennylane_client/issues/18 — Name the Changelogs and Exports operations
- https://github.com/Davidslv/pennylane_client/issues/19 — Name the account, subscription and webhook operations
- https://github.com/Davidslv/pennylane_client/issues/20 — Add PennylaneClient::Webhook.verify!
- https://github.com/Davidslv/pennylane_client/issues/21 — Add rake smoke and the contributor live-verification path
- https://github.com/Davidslv/pennylane_client/issues/22 — Release 0.1.0 via Trusted Publishing
- https://github.com/Davidslv/pennylane_client/issues/23 — Release 1.0.0

---

## Summary

Build `pennylane_client`, a public, MIT-licensed, zero-dependency Ruby gem for the Pennylane Company API v2 as it stands after the 2026 migration. It is a clean-room implementation, built test-first from Pennylane's public documentation only. Every one of the 177 live operations is reachable from day one and gets a stable Ruby name before 1.0. A committed, dated contract snapshot and a generated checklist make "complete" something CI checks, not something we claim.

## Problem Statement

There is no usable Ruby client for the current Pennylane API.

- Pennylane publishes no official SDK in any language.
- The `pennylane` gem (sbounmy) was last released on 2024-05-10 and targets API v1. It predates the 2026 changes.
- The `ruby-pennylane` gem (eddygarcas) was last released on 2022-02-03. The same author's newer repo exposes one generic `call` method and nothing specific to the 2026 changes.

The API itself is large and moving:

- Company API v2 has 178 operations on 127 paths: 94 GET, 46 POST, 31 PUT, 7 DELETE. One is deprecated (`POST /api/external/v2/ledger_attachments`).
- The 2026 migration finished on 2026-07-01 ("no rollback is possible"). The `X-Use-2026-API-Changes` header does nothing now. All 65 list operations use cursor pagination (`items`, `has_more`, `next_cursor`, `limit`). Filters and sort must be re-sent on every page.
- Rate limit: 25 requests per 5 seconds per token. Every response carries `ratelimit-limit`, `ratelimit-remaining` and `ratelimit-reset`. A 429 also carries `retry-after`.
- There is no idempotency on create operations.
- The changelog shows about ten field and operation additions in recent entries.

A hand-written client falls behind an API like this. A client generated at runtime publishes Pennylane's operationIds as its public API, and those make poor Ruby (`deleteCustomerInvoices` deletes one invoice; updates are split between `put*` and `update*`; `ValidateAccountingSupplierInvoice` is PascalCase).

All facts above were verified by independent agents on 2026-09-29 and 2026-09-30.

## Proposed Solution

### Identity

- Gem `pennylane_client`, `require "pennylane_client"`, module `PennylaneClient`.
- `PennylaneClient.new(token:)` returns a `PennylaneClient::Client`. `PennylaneClient::Client.new` also works. This is the Restforce pattern.
- Repo at `~/projects/me/products/pennylane_client`, GitHub `Davidslv/pennylane_client`, MIT.
- README and gemspec summary say "unofficial, not affiliated with Pennylane".

```ruby
client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))

client.customer_invoices.list(filter: [{ field: "status", operator: "eq", value: "draft" }])
      .each { |invoice| puts invoice[:invoice_number] }   # follows next_cursor, re-sends filters
client.customer_invoices.find(42)
client.customer_invoices.finalize(42)
client.file_attachments.upload(File.open("receipt.pdf"))
client.call(:getCustomerInvoiceCustomHeaderFields, customer_invoice_id: 42)   # any registered operation
```

### Scope

- **In 1.0:** Company API v2, 177 live operations. The deprecated `postLedgerAttachments` is listed as `skipped: deprecated` in the checklist, with `postFileAttachments` as its replacement.
- **In 1.0:** `PennylaneClient::Webhook.verify!` for inbound webhooks (HMAC-SHA256 over `"{t}.{raw_body}"`, constant-time compare, 300 second default tolerance).
- **Later:** an OAuth 2.0 helper, and the Firm API (44 operations, different path prefix, 5 requests per second, some `page`/`per_page` pagination, needs a firm account).
- **Out:** the Firm Group API (34 operations, access on request only).

### Contract snapshot and checklist

`tools/snapshot_contract.rb` builds the contract from two sources and requires them to agree:

1. The documented surface: `https://pennylane.readme.io/llms.txt`, then every `/reference/*.md` page, then the OpenAPI fragment embedded in each page. Some pages use a four-backtick fence; the parser must handle both.
2. `https://pennylane.readme.io/openapi/accounting.json`, the full spec. It is not linked from the docs, so it is a cross-check only. If it disappears the tool warns and carries on with source 1.

Committed under `docs/api/`, machine-generated, never hand-edited:

- `contract/<date>/operations.json`: every operation, normalised and sorted. operationId, method, path, parameters, request and response schemas, scopes, deprecated flag, source URL.
- `contract/<date>/guides/`: the guides behaviour depends on (rate limiting, pagination, errors, webhooks, OAuth, the 2026 migration), each with source URL and retrieval date.
- `CHECKLIST.md`: one row per operation, grouped by resource group, with columns `registered`, `named`, `live`, and the behaviour test that proves it.

Dated folders are kept, so "what did 0.3.0 target?" always has an answer.

The checklist is generated, never ticked by hand. CI regenerates it and fails if the committed copy differs. A weekly GitHub Action re-runs the snapshot and opens an issue listing new, removed and changed operations. It never auto-commits. A new snapshot lands only in a PR with the matching code.

### Architecture

The council (five independent agents: maintainer economics, caller ergonomics, SOLID and testability, ecosystem evidence, red team) rejected hand-written-only and runtime-from-spec designs and converged on this shape. See D3.

```
 DEV TIME (rake tasks, never shipped)              RUN TIME (the gem, zero runtime deps)
 ====================================              ======================================

 pennylane.readme.io                                caller code
   llms.txt ─┐                                        │
   /reference/*.md (fragments) ─┤                     │ PennylaneClient.new(token:)
   openapi/accounting.json ─────┤ (cross-check)       ▼
                                ▼                  ┌──────────────────────────────────────┐
                  tools/snapshot_contract.rb       │ PennylaneClient::Client              │
                                │                  │  wiring only; builds the pipeline    │
                                ▼                  │  #customer_invoices #customers ...   │
          docs/api/contract/<date>/                │  #call(:operationId, **params)  ◄────┼── any Registered op
            operations.json   guides/              └───────┬──────────────────────────────┘
                 │       │                                 │ one per resource group (~30)
   rake contract:sync    rake checklist                    ▼
                 │       │                         ┌──────────────────────────────────────┐
                 ▼       ▼                         │ Resources::CustomerInvoices < Resource│
 lib/.../operations.rb   docs/api/CHECKLIST.md     │  def find(id)     = call(:getCust..)  │ HAND-WRITTEN
 (GENERATED, frozen)     registered|named|live     │  def list(**f)    = paginate(:get..)  │ Named ops
       │                 (CI fails if stale)       │  def finalize(id) = call(:finalize..) │
       │                                           └───────┬──────────────────────────────┘
       │  weekly drift job: re-snapshot,                   │ call / paginate / upload
       │  diff, open issue (never commits)                 ▼
       │                                           ┌──────────────┐    ┌─────────────────────┐
       └──────────────────────────────────────────►│ Registry     │    │ Paginator           │
                    operationId → Operation        │ (frozen)     │    │ cursor, has_more,   │
                    (method, path, paginated,      └──────┬───────┘    │ re-sends filter/sort│
                     body kind, success code)             │            │ → Enumerator::Lazy  │
                                                          ▼            └─────────┬───────────┘
                                                   ┌──────────────────────────────▼───────────┐
                                                   │ Executor                                  │
                                                   │  Operation + params → Request             │
                                                   │  path params / query / body split         │
                                                   │  Encoder: BigDecimal→"F", Date/Time→ISO   │
                                                   │  Multipart for the 7 upload ops           │
                                                   │  Response → deep-frozen Hash | true (204) │
                                                   │  status → PennylaneClient::Error subclass │
                                                   └──────────────────────┬───────────────────┘
                                                                          │ Request
                        MIDDLEWARE PIPELINE (each: call(request) → response, injected)
   ┌────────────────┐   ┌──────────────────────────┐   ┌─────────────────────────────────────┐
   │ Auth           │──►│ RateLimit                │──►│ Retry                               │──┐
   │ token provider │   │ token bucket 25 / 5 s    │   │ 429: any method, sleep retry-after  │  │
   │ String|#call   │   │ keyed by SHA-256(token)  │   │ 5xx/network: GET only (D5)          │  │
   │ never logged   │   │ ratelimit-* headers      │   │ 3 attempts, full jitter, 30 s cap   │  │
   └────────────────┘   │ self-correct the bucket  │   │ retry: :always opt-in               │  │
                        │ clock + sleeper injected │   └─────────────────────────────────────┘  │
                        └────────────┬─────────────┘                                            │
                                     │ shared per token, process-wide default                   │
                                     ▼                                                          ▼
                        ┌──────────────────────────┐              ┌──────────────────────────────────┐
                        │ LimiterRegistry          │              │ Transport  (interface)           │
                        │ injectable (bring your   │              ├──────────────────────────────────┤
                        │ own, e.g. Redis-backed)  │              │ NetHttpTransport                 │
                        └──────────────────────────┘              │  keep-alive, connection/thread   │
                                                                  │  timeouts 5/30/30, uploads 300   │
                                                                  ├──────────────────────────────────┤
                                                                  │ FakePennylane (test support)     │
                                                                  │  enforces 25/5 s, real headers,  │
                                                                  │  misbehaves on demand (stress)   │
                                                                  └──────────────┬───────────────────┘
                                                                                 │ HTTPS
                                                                                 ▼
                                                                  app.pennylane.com/api/external/v2

 SIDE PIECES
   PennylaneClient::Webhook.verify!(raw_body, signature_header, secret:, tolerance: 300)
     HMAC-SHA256("{t}.{raw_body}") + fixed_length_secure_compare → frozen event Hash | SignatureError
   PennylaneClient.configure { logger, on_request }   ← every request, retry and limiter wait emits an event
   PennylaneClient::Error
     ├ AuthenticationError (401)   ├ PermissionError (403)   ├ NotFoundError (404)
     ├ ConflictError (409)         ├ ValidationError (422)   ├ RateLimitError (429, #retry_after)
     ├ ServerError (5xx)           ├ ConnectionError / TimeoutError
     └ SignatureError (webhooks)
```

- **`lib/pennylane_client/operations.rb`** is generated from the snapshot by `rake contract:sync`. Plain data only, one `Operation` row per operationId: method, path, pagination, body kind (json or multipart), success code. Sorted, so drift shows as one-line diffs. Every live operation is **Registered** from the first commit.
- **Resource classes are hand-written.** Each public method is a one-liner born from a failing behaviour test, e.g. `def finalize(id) = call(:finalizeCustomerInvoice, id:)`. The Ruby name is chosen by a person and is a promise to callers. If Pennylane renames an operationId, one generated row changes and the Ruby method does not.
- **`client.call(:operationId, **params)`** reaches any Registered operation, including ones not yet Named.
- **Runtime classes each have one reason to change:** `Operation`, `Registry`, `Executor`, `Paginator`, the middleware (`Auth`, `RateLimit`, `Retry`), `Transport`, `Client`. Every class depends on a callable, never on `Net::HTTP`. Clock and sleeper are injected.
- **No metaprogramming.** No `define_method`, no `method_missing`. RBS signatures in `sig/` are hand-written and checked in CI.
- **Awkward operations are handled on purpose, not hidden behind CRUD:** 11 non-CRUD actions (finalize, mark as paid, send by email, validate, lettering), DELETE with a body (`deleteLedgerEntryLinesUnletter`), 3 async exports (POST then poll), 26 success responses with no body (return `true`), 15 `oneOf` request bodies, 7 multipart uploads, the changelog operations (including `getQuoteChanges`, which is tagged Quotes), `getPaRegistrations` (returns cursor fields but takes no cursor), and the 2 operations tagged "Hidden".

### Values

- Responses are deep-frozen Hashes with symbol keys, exactly as Pennylane sends them. Money stays a decimal string (`"230.32"`), dates stay ISO 8601 strings. No typed models. See D6.
- The request encoder converts `BigDecimal` to `to_s("F")` (plain `to_json` would send `"0.23032e3"`) and `Date`/`Time` to ISO 8601. It checks `defined?(BigDecimal)` and never requires it. Everything else passes through.

### Authentication

- `token:` accepts a String or anything that responds to `#call` and returns the current token.
- On 401 the gem raises `PennylaneClient::AuthenticationError`. It never refreshes on its own.
- The token never appears in logs, `inspect`, exceptions or the `on_request` event. Rate-limiter keys use a SHA-256 of the token.

### Resilience

| Concern | Policy |
|---|---|
| Client-side limiter | Token bucket, 25 per 5 s, one per token. Shared across clients and threads in the process by default. Injectable. |
| Self-correction | `ratelimit-remaining` and `ratelimit-reset` on every response update the bucket, so another process draining the same token is noticed. |
| 429 | Retry any method, sleep `retry-after` (capped). Assumes a 429 means the request was not run; to be confirmed live. |
| 500, 502, 503, 504, network errors | Retry GET only. Never POST, PUT or DELETE. See D5. |
| Backoff | Max 3 attempts, exponential with full jitter, total wait capped at 30 s by default. |
| Timeouts | Open 5 s, read 30 s, write 30 s. Multipart uploads 300 s read and write. All configurable. |
| Opt-in | `client.call(..., retry: :always)` for callers who know an operation is safe to repeat. |
| Visibility | Every request, retry and limiter wait fires `on_request` with a plain Hash. |

A Redis-backed cross-process limiter would break zero-deps. Callers can inject their own through the limiter interface.

### Testing

| Word | Meaning | Runs |
|---|---|---|
| Tested | Every Named operation has a TDD behaviour test that stubs the exact method and path, written by hand from the reference page. The runtime pieces have their own suites. | `rake`, offline, webmock |
| Validated | The checklist `live` column per operation: `sandbox-verified <date> (by @user)` or `unverified: no sandbox access`. Starts as unverified for every row. The README states the count. | `rake smoke`, credential-gated |
| Load tested | Against `FakePennylane`, which enforces 25 per 5 s and returns real headers. N threads sustain close to the limit with zero 429s; keep-alive reuse confirmed; flat memory while paginating 100k items. Results in `docs/performance.md`. | `rake load` |
| Stress tested | `FakePennylane` misbehaves: 429 storms, 5xx bursts, slow responses, resets, malformed JSON, 100 MB uploads, several processes on one token. Retries stay bounded, no deadlocks, no leaked threads or sockets, correct error classes, no non-GET retried after a 5xx. 30-minute soak for memory. | `rake stress` |
| Never | No load or stress testing of Pennylane's servers, sandbox included. | |

The contract test (table against snapshot) is a sanity check only, because the table is generated from the snapshot. It does not count towards `named` in the checklist. Only behaviour tests do.

### Conventions and project standards

- Baseline is `bundle gem pennylane_client --test=minitest --linter=rubocop --ci=github --mit --changelog` from Bundler 4.0.21. `sig/` RBS, `# frozen_string_literal: true` in every file, `require_relative` in the gemspec, `spec.files` from `git ls-files`, dev dependencies in the Gemfile, `lockfile false`.
- RuboCop runs in the default `rake` task.
- `required_ruby_version >= 3.3`. CI matrix 3.3, 3.4, 4.0. Move to `>= 3.4` after Ruby 3.3 reaches end of life (expected 2027-03-31).
- Zero runtime dependencies: `net/http`, `json`, `uri`, `openssl`, `securerandom` are still default gems in Ruby 4.0. `logger` and `base64` are now bundled gems, so the library avoids them.
- Release by Trusted Publishing (`rubygems/release-gem` on a `v*` tag, OIDC, Sigstore attestations on), `rubygems_mfa_required`, `bundler-audit` in CI.
- The repo ships the four layers from notes#117: root community-health files, `.github/` templates and automation, layered `docs/`, and `llms.txt` plus `AGENTS.md`. Contributor Covenant 2.1 replaces the scaffold's code-of-conduct link. CHANGELOG follows Keep a Changelog 1.1 and SemVer.
- Versioning: 0.x releases as resource groups become Named. 1.0.0 when every live operation is Named.

### Delivery outline (for `/break-down`)

1. Scaffold, conventions, and the notes#117 layers.
2. Contract snapshot tool, dated snapshot, generated `CHECKLIST.md`, stale-checklist CI check, weekly drift workflow.
3. Runtime core: Operation, generated table, Executor, errors, encoder, Paginator, multipart, middleware (Auth, RateLimit, Retry), NetHttpTransport. `client.call` works for every Registered operation.
4. `FakePennylane`, `rake load`, `rake stress`, `docs/performance.md`.
5. Resource groups, one sub-issue each, each row of the checklist in its body. Largest groups: Customer Invoices 23, Customers 15, Mandates 14, Supplier Invoices 14, Transactions 11, Quotes 11, Changelogs 9, Commercial Documents 8.
6. `Webhook.verify!`.
7. `rake smoke` and the contributor path for live verification.
8. Release 0.1.0 after phases 1 to 4 and the first resource groups; 1.0.0 when every live operation is Named.

## Decisions

#### D1: Gem `pennylane_client` with module `PennylaneClient`, not `Pennylane::Client`

**Decision:** Publish as `pennylane_client`, `require "pennylane_client"`, module `PennylaneClient`, with `PennylaneClient.new(token:)` returning `PennylaneClient::Client`.

**Alternatives considered:** `pennylane-client` with `Pennylane::Client`; `pennylane-rb` with `Pennylane`; asking sbounmy to transfer the `pennylane` name; making `PennylaneClient` a class (the redis-client pattern).

**Why this one:** The `pennylane` gem already ships `lib/pennylane/client.rb` defining `Pennylane::Client`. A verifier loaded both and ours was shadowed. The RubyGems naming guide says a dash means "adding functionality to another gem", so `pennylane-client` would read as a plugin for sbounmy's gem. Underscore names map to one module, like `ruby_parser` and `RubyParser`. Of 45 gems checked, unofficial clients that took the vendor namespace caused real clashes (`ruby-openai` and `openai` both define `OpenAI`). The `.new` shortcut hides the `PennylaneClient::Client` stutter; precedent in `Restforce.new`. A module keeps the namespace and the client as separate responsibilities.

**Date:** 2026-09-30

#### D2: Clean room: Pennylane's public documentation and observed sandbox behaviour only

**Decision:** No person or agent working on the gem reads the source, README or tests of any other Pennylane client in any language. Contradictions in the docs are settled by the sandbox and recorded, never by copying another client.

**Alternatives considered:** Reading the existing Ruby gems, the Python and PHP SDKs and `mcp-pennylane` for hints.

**Why this one:** It keeps the MIT licence free of any derived code, and it forces behaviour to be proven against Pennylane rather than against someone else's guess. The cost is real: when the docs are unclear and there is no sandbox, the answer is to record the ambiguity, not to look. A verifier opened sbounmy's `client.rb` once, only to confirm the name clash in D1. Nothing from it carries over.

**Date:** 2026-09-30

#### D3: Generated operation table, hand-written named methods, `call` for everything

**Decision:** The operation table is generated from the contract snapshot. Public Ruby methods are hand-written one-liners, each born from a failing behaviour test. `client.call(:operationId)` reaches every Registered operation. Behaviour tests carry the independent check, with expected paths written by hand from the docs.

**Alternatives considered:** Hand-written requests per operation (Octokit); methods defined at runtime from the spec; a full code generator (AWS v3, Stripe, Stainless); a hand-typed operation table; curated named methods for high-value groups only; one-liners generated from a `naming.yml`.

**Why this one:** A five-agent council scored all options. Runtime generation was abandoned by AWS (v2 to v3, 2016), Google (0.8 to 0.9) and Stripe (6.4.0), and it hides methods from RBS, YARD and ruby-lsp. Hand-writing everything left Octokit covering about 523 of GitHub's 1,231 operations. Full generators pass Pennylane's poor operationIds through as public names and turn into a second product. Generating only the data table removes transcription work; hand-writing the methods keeps naming a human decision and fits the TDD loop. The trade-off accepted: the contract test between table and snapshot proves nothing on its own, so correctness rests on the hand-written behaviour tests.

**Date:** 2026-09-30

#### D4: Current RubyGems and Bundler conventions, plus the notes#117 standard, as the baseline

**Decision:** Start from `bundle gem` (Bundler 4.0.21) with minitest and RuboCop, ship `sig/` RBS, require Ruby >= 3.3, release by Trusted Publishing, and ship every notes#117 layer. Contributor Covenant 2.1 replaces the scaffold's code-of-conduct link.

**Alternatives considered:** Copying airtable-rb's layout, which misses about twelve current conventions (naming, `sig/`, frozen string literals, `require_relative`, Trusted Publishing, EOL Rubies in CI); the scaffold's own `>= 3.2.0` default.

**Why this one:** Ruby 3.2 reached end of life on 2026-04-01, so the scaffold default is already stale. airtable-rb is the template for resilience, contract drift and the smoke suite, not for scaffolding. notes#117 wins where it and the scaffold disagree, because GitHub only detects the community files in their recognised formats.

**Date:** 2026-09-30

#### D5: Never retry POST, PUT or DELETE after a 5xx or network error

**Decision:** Retry 429 for every method. Retry 5xx and network errors for GET only. Callers can opt in per call with `retry: :always`.

**Alternatives considered:** Retry every method on 5xx, as many clients do; retry PUT and DELETE because HTTP calls them idempotent.

**Why this one:** Pennylane does not enforce idempotency on creates. Many of its PUTs and POSTs have side effects (`finalize`, `mark_as_paid`, `send_by_email`, lettering). After a timeout the client cannot know whether the first attempt ran, and a duplicate invoice or a second email is worse than an error the caller can handle. The 429 rule rests on the assumption that a rate-limited request was not run; the smoke suite checks it when sandbox access exists.

**Date:** 2026-09-30

#### D6: Responses returned as Pennylane sends them, no typed models, money as strings

**Decision:** Responses are deep-frozen Hashes with symbol keys. Money and dates stay as strings. Only the request encoder converts `BigDecimal`, `Date` and `Time`.

**Alternatives considered:** Typed models per schema (Stripe, Stainless); a thin record wrapper with accessors; converting money to `BigDecimal` and dates to `Date` on the way out.

**Why this one:** Money fields are `{"type": "string"}` with no format marker, so converting them needs a hand-kept field list that drifts with every Pennylane change. `bigdecimal` became a bundled gem in Ruby 3.4, so requiring it breaks zero-deps. Typed models are where the size went in Twilio (330k LOC) and Anthropic (81k LOC of models against 9.4k of resources). Pennylane's responses have 3,249 properties. Plain Hashes also work with pattern matching. Changing this after 1.0 would break every caller, so it is decided now.

**Date:** 2026-09-30

#### D7: No OAuth in 1.0, and no automatic token refresh ever inside the client

**Decision:** 1.0 ships a token-provider seam (`token:` as String or callable) and raises `AuthenticationError` on 401. An OAuth helper comes later. The client never refreshes a token itself.

**Alternatives considered:** A full OAuth helper in 1.0 with refresh-on-401.

**Why this one:** OAuth app credentials need Pennylane partner approval, which we do not have, so the helper could not be validated, and the docs disagree on the token URL (`/oauth/token` in the guide, `/oauth/oauth/token` in the spec). Each refresh rotates the refresh token and invalidates the old access token, so two processes refreshing at once lock the integration out. Only the caller can coordinate that across processes.

**Date:** 2026-09-30

#### D8: Publish as ordinary open source after reading Pennylane's API terms

**Decision:** Build and publish the gem as a normal public MIT project, with an "unofficial, not affiliated" notice.

**Alternatives considered:** Asking Pennylane Partnerships for written permission first; publishing a facts-only snapshot instead of their OpenAPI fragments; pausing.

**Why this one:** David's call. The API terms (last updated January 2024) contain clauses a future reader will notice: 3.4(d) derivative works, 3.4(f) redistribution of API materials, 3.4(l) open-source licence terms on "API Integrations", 3.4(m) suggesting affiliation, and 4.3 a licence grant to Pennylane. Whether a general client library counts as an "API Integration" is unclear, and David has no account and has accepted no terms. The project proceeds like any other open-source API client.

**Date:** 2026-09-30

## Open Questions

- **Live validation.** David has no Pennylane account. Signup needs a French SIRET, and a sandbox needs a paid Essential plan behind it. Every `live` row starts as `unverified: no sandbox access` until a contributor with an account runs `rake smoke`. Owner: David, if a contributor or partner route appears.
- **429 and non-GET requests.** D5 assumes a 429 means the request was not run. Confirm on a sandbox.
- **Webhook live check.** `Webhook.verify!` is tested against vectors built from the documented scheme. A real signed delivery needs sandbox access.
- **OAuth helper.** Deferred to a later minor. Blocked on partner access and on settling the token URL.
- **Firm API.** A separate proposal if David gets a firm account.
- **The `pennylane` gem name.** Asking sbounmy to transfer it is possible but unnecessary under D1. Low priority.
- **`accounting.json` stability.** The full-spec URL is not linked from the docs and may vanish. The snapshot tool degrades to the per-page source.
