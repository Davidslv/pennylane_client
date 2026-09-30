# pennylane_client design diagram

The whole gem on one page: the dev-time contract tooling on the left, the runtime request path on the right, and the side pieces (webhooks, configuration, errors) at the bottom.

Source: [proposal 0001](../../proposals/0001-pennylane-client-gem.md), accepted 2026-09-30. If the code and this diagram disagree, the code wins and this diagram has a bug.

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
   ┌────────────────┐   ┌─────────────────────────────────────┐   ┌──────────────────────────┐
   │ Auth           │──►│ Retry                               │──►│ RateLimit                │──┐
   │ token provider │   │ 429: any method, sleep retry-after  │   │ token bucket 25 / 5 s    │  │
   │ String|#call   │   │ 5xx/network: GET only (D5)          │   │ keyed by SHA-256(token)  │  │
   │ never logged   │   │ 3 attempts, full jitter, 30 s cap   │   │ ratelimit-* headers      │  │
   └────────────────┘   │ retry: :always opt-in               │   │ self-correct the bucket  │  │
                        └─────────────────────────────────────┘   │ clock + sleeper injected │  │
                                                                  └────────────┬─────────────┘  │
                        ┌──────────────────────────┐                           │                │
                        │ LimiterRegistry          │◄──────────────────────────┘                │
                        │ injectable (bring your   │  shared per token,                         │
                        │ own, e.g. Redis-backed)  │  process-wide default                      │
                        └──────────────────────────┘                                            ▼
                                                                  ┌──────────────────────────────────┐
                                                                  │ Transport  (interface)           │
                                                                  ├──────────────────────────────────┤
                                                                  │ NetHttpTransport                 │
                                                                  │  keep-alive, connection/thread   │
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

## How to read it

- **Dev time** never ships in the gem. It turns Pennylane's published docs into a dated contract snapshot, the generated operation table, and `CHECKLIST.md`.
- **Run time** is one path: `Client` → a hand-written `Resource` method → `Registry` lookup → `Executor` → the middleware pipeline (`Auth` → `Retry` → `RateLimit`) → a `Transport`. Retry sits outside RateLimit so every attempt takes its own call from the bucket and every response corrects it. An `Instrument` middleware next to the Transport records each attempt.
- Every box below `Client` is injected, so tests, load runs and stress runs swap `NetHttpTransport` for `FakePennylane` without touching anything else.
