# pennylane_client design diagram

The whole gem on one page: the dev-time contract tooling on the left, the runtime request path on the right, and the side pieces (webhooks, configuration, errors) at the bottom. The prose version is [docs/architecture.md](../architecture.md).

Source: [proposal 0001](../../proposals/0001-pennylane-client-gem.md), decisions D1 to D11. Every box is checked against `lib/`. If the code and this diagram disagree, the code wins and this diagram has a bug.

`[public]` marks what the README's Public API section covers (D10). Every other runtime box is `@api private`.

```
 DEV TIME (rake tasks, never shipped)              RUN TIME (the gem, zero runtime deps)
 ====================================              ======================================

 pennylane.readme.io                                caller code
   llms.txt ────────────────────┐                     │
   /reference/*.md (fragments) ─┤                     │ PennylaneClient.new(token:)            [public]
   openapi/accounting.json ─────┤ (cross-check)       ▼
                                ▼                  ┌──────────────────────────────────────────┐
                  tools/snapshot_contract.rb       │ Client                          [public] │
                  (rake contract:snapshot)         │  wiring only; composes the middleware    │
                                │                  │  #call(:operationId, body = nil,         │
                                ▼                  │        retry: nil, **params)             │
          docs/api/contract/<date>/                │  #paginate  #pages                       │
            operations.json   guides/              │  #customer_invoices #customers ... (32)  │
                 │       │                         └──────┬───────────────────────────────────┘
   rake contract:sync    rake checklist                   │ one Resource per group
                 │       │                                ▼
                 ▼       ▼                         ┌──────────────────────────────────────────┐
 lib/.../operations.rb   docs/api/CHECKLIST.md     │ Resources::CustomerInvoices < Resource   │
 OPERATIONS (GENERATED)  registered|named|live     │  def find(id) = call(:getCustomerInv..)  │ HAND-WRITTEN
       │                 README live count         │  def list(**f) = paginate(:getCust..)    │ Named methods
       │                 (rake stale fails the     │  call_on / paginate_on: a keyword that   │ [public]
       │                  gate if out of date)     │  names a path param raises               │
       │                                           │  every write takes retry:  (D11)         │
       │  weekly drift job (contract-drift.yml):   │  @note Experimental: on Hidden/alpha/    │
       │  re-snapshot, diff, open a `drift`        │  beta ones (D9)                          │
       │  issue (never commits)                    └──────┬───────────────────────────────────┘
       │                                                  │ call / paginate
       │                                                  ▼
       │                                           ┌──────────────┐    ┌──────────────────────┐
       └──────────────────────────────────────────►│ Registry     │    │ Paginator            │
                    operationId → Operation        │ (frozen)     │    │ largest page, resends│
                    (verb, path, paginated,        │ unknown id → │    │ filter/sort, not     │
                     max_limit, body kind,         │ UnknownOp... │    │ start_date; has_more │
                     success, deprecated)          └──────┬───────┘    │ → Enumerator::Lazy   │
                                                          │            └──────────┬───────────┘
                                                          ▼                       │
                                                   ┌──────────────────────────────▼────────────┐
                                                   │ Executor                                  │
                                                   │  Operation + params → Request             │
                                                   │  path params: escaped; nil, "", ".", ".." │
                                                   │    raise ArgumentError                    │
                                                   │  rest → JSON body | Multipart | query     │
                                                   │  Encoder: BigDecimal→"F", Date/Time→ISO   │
                                                   │  Multipart streams the 7 upload ops       │
                                                   │  2xx → deep-frozen Hash | true (empty)    │
                                                   │  2xx not JSON / not UTF-8 → Error         │
                                                   │  other status → Error subclass            │
                                                   └──────────────────────┬────────────────────┘
                                                                          │ Request [public]
                        MIDDLEWARE PIPELINE (each: call(request) → Response)
   ┌────────────────┐   ┌───────────────────────────────────┐   ┌──────────────────────────┐
   │ Auth           │──►│ Retry                             │──►│ RateLimit                │──┐
   │ String | #call │   │ 429: any verb, retry-after        │   │ Limiter per token,       │  │
   │ asked once per │   │ 5xx / no response: GET only (D5)  │   │ keyed by SHA-256(token)  │  │
   │ call; never    │   │ 3 attempts, full jitter,          │   │ waits → :wait event      │  │
   │ logged         │   │ 30 s cap; retry: :always opt-in   │   │ ratelimit-* headers      │  │
   └────────────────┘   │ → :retry event                    │   │ correct the bucket       │  │
                        └───────────────────────────────────┘   └────────────┬─────────────┘  │
                        ┌──────────────────────────────┐                     │                │
                        │ LimiterRegistry     [public] │◄────────────────────┘                │
                        │ process-wide default, or     │   ┌──────────────────────────┐       │
                        │ bring your own (Redis...)    │   │ Limiter                  │       │
                        │ drops idle limiters (60 s)   │──►│ 25 / 5 s bucket          │       │
                        └──────────────────────────────┘   │ skewed reset ignored,    │       │
                                                           │ remaining still applied  │       │
                                                           └──────────────────────────┘       │
                                                                  ┌───────────────────────────▼──────┐
                                                                  │ Instrument                       │
                                                                  │ one :request event per attempt   │
                                                                  └───────────────┬──────────────────┘
                                                                                  ▼
                                                                  ┌──────────────────────────────────┐
                                                                  │ Transport (interface)   [public] │
                                                                  │ call(Request) → Response         │
                                                                  ├──────────────────────────────────┤
                                                                  │ NetHttpTransport        [public] │
                                                                  │  keep-alive, 1 connection per    │
                                                                  │  host per fiber, idle 10 s       │
                                                                  │  timeouts 5/30/30, uploads 300   │
                                                                  │  max_retries 0                   │
                                                                  │  incomplete call → drop the      │
                                                                  │  connection                      │
                                                                  │   └ ConnectionOwners: fiber →    │
                                                                  │     connections (weak); finished │
                                                                  │     fibers' ones closed when a   │
                                                                  │     new connection opens         │
                                                                  ├──────────────────────────────────┤
                                                                  │ FakePennylane (test support)     │
                                                                  │  enforces 25/5 s, real headers,  │
                                                                  │  misbehaves on demand (stress)   │
                                                                  └──────────────┬───────────────────┘
                                                                                 │ HTTPS
                                                                                 ▼
                                                                  app.pennylane.com/api/external/v2

 SIDE PIECES
   PennylaneClient::Webhook.verify!(raw_body, signature_header, secret:, tolerance: 300)   [public]
     HMAC-SHA256("{t}.{raw_body}") + fixed_length_secure_compare → frozen event Hash | SignatureError
   PennylaneClient.configure { logger, on_request }                                       [public]
     Instrumentation: every attempt, retry and rate-limit wait → one log line + one event; never raises
   PennylaneClient::Upload(source, filename:, content_type:)                              [public]

   PennylaneClient::Error (status, code, details, body, headers)                          [public]
     ├ ValidationError (400, 422)    ├ AuthenticationError (401)   ├ PermissionError (403)
     ├ NotFoundError (404)           ├ ConflictError (409)         ├ RateLimitError (429, #retry_after)
     ├ ServerError (5xx)             ├ ConnectionError             ├ TimeoutError
     ├ ExportError (#export)         └ SignatureError (webhooks)
     any other status → Error itself; error bodies with bad UTF-8 are scrubbed for the message

   PennylaneClient::UnknownOperationError < ArgumentError                                 [public]
```

## How to read it

- **Dev time** never ships in the gem. It turns Pennylane's published docs into a dated contract snapshot, the generated operation table and `CHECKLIST.md`.
- **Run time** is one path: `Client` → a hand-written `Resource` method → `Registry` → `Executor` (through the `Paginator` for lists) → the middleware (`Auth` → `Retry` → `RateLimit` → `Instrument`) → a `Transport`. Retry sits outside RateLimit, so every attempt takes its own call from the bucket and every response corrects it. Instrument sits next to the Transport, so each attempt is one event and its `duration` has no wait in it.
- `Client` takes the Transport, the LimiterRegistry, the logger and `on_request` as constructor arguments, so tests, load runs and stress runs swap `NetHttpTransport` for `FakePennylane` without touching anything else.
- `[public]` boxes are covered by SemVer from 1.0.0. Experimental named methods may change in a minor release; the README's Stability section lists them.
