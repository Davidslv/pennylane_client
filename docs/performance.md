# Performance

How the client behaves under load and when Pennylane misbehaves, measured against `FakePennylane`. Nothing here ever reaches Pennylane's servers, sandbox included ([AGENTS.md](../AGENTS.md), rule 7).

## Reproduce

```sh
bundle exec rake load            # about 25 s
bundle exec rake stress          # about 40 s
bundle exec rake "stress[30]"    # the same, plus a 30-minute soak
```

Each prints a results block after the Minitest summary; the tables below are copied from it. CI runs `rake load` on every pull request and push to `main` (the `Load test` job in `ci.yml`). `rake stress` runs on demand from the Actions tab (the `Stress` workflow, with a `soak_minutes` input).

`LOAD_THREADS` and `LOAD_SECONDS` change the size of the sustained load run.

## The fake

`FakePennylane` (`test/support/fake_pennylane.rb`) is a Transport, so a Client can use it in process. `FakePennylane::Server` (`test/support/fake_pennylane/server.rb`) serves the same fake over HTTP/1.1 with keep-alive on 127.0.0.1, one thread per connection, so the real `NetHttpTransport` runs end to end. The fake:

- Enforces 25 requests per 5 s per token, as [the rate-limiting guide](api/contract/2026-09-30/guides/rate-limiting.md) describes, and answers every request with `ratelimit-limit`, `ratelimit-remaining` and `ratelimit-reset` (a Unix time in whole seconds). A request over the limit gets a 429 with `retry-after` and the documented plain-text body, and is not counted.
- Places its windows on multiples of 5 s since the epoch, so every reset is a whole second, as Pennylane reports it. The guide does not say how Pennylane places its windows; this is the simplest reading that fits the headers. The client does not depend on it: it takes the window end from `ratelimit-reset`.
- Serves cursor pages of generated items for a path registered with `collection(path, size:)`, built one page at a time.
- Reads a request body to the end and answers with its size, so an upload can be checked.
- Misbehaves on demand with `inject(kind, times:)`: `:rate_limited` (a 429 storm), `:server_error`, `:slow`, `:hang` (silent, then closed), `:reset` (a TCP reset, SO_LINGER 0) and `:malformed` (a 200 whose JSON is cut short).
- Counts every answer by verb and status, `count("POST 503")`, and the server counts connections.

The gate tests the fake itself: `test/fake_pennylane_test.rb`, `test/fake_pennylane_faults_test.rb` and `test/fake_pennylane_server_test.rb`.

## rake load

Recorded 2026-09-30 on Ruby 4.0.7, arm64-darwin25 (Apple silicon laptop), on the code after the pre-1.0 review fixes.

| Run | Result |
|---|---|
| 8 threads, one token, 20 s, real sockets | 133 calls in 24.9 s. **25 requests in every full 5 s window (100% of the limit).** 0 answered 429, 0 retries, 40 limiter waits, **8 connections for 8 threads**. |
| Paginate 100k items, in process | 100,000 items in 1,000 pages in 0.1 s. Live objects after a full GC: -1 slots between 20k and 100k items. RSS 47.1 to 49.0 MB. |

The run fails unless every full window carries at least 90% of the limit, the fake answers no 429, the client retries nothing and each thread opens exactly one connection. The pagination run fails if live objects grow by 50,000 slots or more between 20k and 100k items; keeping the items would add several hundred thousand. It uses a limit of 1,000,000 on both sides because it measures memory, not the rate limit.

Requests are placed in windows by the time their response arrived, so a request sent just before a window ends can count in the next one; the 90% floor absorbs that. The partial first and last windows are left out of the per-window count. Requests per second over the whole run overstates use for that reason: the first window may be a fraction of a second long and still carry 25 requests.

### Found and fixed: a reconnect after every rate-limit wait

The first load run opened 40 connections for 8 threads, one per limiter wait. `Net::HTTP` drops a connection that has been idle for more than `keep_alive_timeout`, 2 s by default, and a wait for the next window lasts up to 5 s. Against Pennylane every wait would have cost a new TCP connection and TLS handshake. `NetHttpTransport` now keeps idle connections for 10 s (`keep_alive_timeout:`), past one window. `Net::HTTP` still checks for EOF before reusing a connection, so one the server has closed is replaced rather than written to; `test/fake_pennylane_server_test.rb` checks that a POST after such a close succeeds. 10 s rather than longer keeps rare the case where the server closes a connection in the instant a write is sent on it ([architecture](architecture.md#where-this-design-would-strain)). The run now asserts one connection per thread.

## rake stress

Recorded 2026-09-30 on Ruby 4.0.7, arm64-darwin25, on the code after the pre-1.0 review fixes. Eight threads per scenario, each on its own token so the fault is measured rather than the shared budget. The transport's read timeout is 0.5 s. "Attempts" is what the fake received.

| Scenario | Outcome | Attempts | Retries | Seconds |
|---|---|---|---|---|
| 429 storm, `retry-after: 1`, GET + POST + PUT + DELETE | 32 `RateLimitError` | 96 (3 per call) | 64 | 21.5 |
| 429 storm, `retry-after: 60` | 8 `RateLimitError` | 8 (the wait passes the 30 s cap) | 0 | 0.0 |
| 5xx burst of 16, GET | 22 ok, 2 `ServerError` | 38 | 14 | 1.2 |
| 5xx on every POST, PUT and DELETE | 24 `ServerError` | **24 (one per write)** | 0 | 0.0 |
| The same with `retry: :always` | 8 `ServerError` | 24 (3 per call) | 16 | 1.2 |
| Slow answers, 0.3 s of a 0.5 s read timeout | 32 ok | 32 | 0 | 1.2 |
| Hang past the 0.5 s read timeout | 32 `TimeoutError` | 48: 24 GET (3 each), **24 writes (1 each)** | 16 | 4.1 |
| Connection reset | 32 `ConnectionError` | 48: 24 GET (3 each), **24 writes (1 each)** | 16 | 1.5 |
| Malformed JSON | 32 `PennylaneClient::Error` | 32 | 0 | 0.0 |
| 4 x 100 MB uploads, each first refused with a 429 | 4 ok | 8 | 4 | 2.2, RSS +6.2 MB |
| 4 processes x 12 calls on one token | 48 ok | 51 (3 answered 429) | 3 | 3.0 |

The 5xx burst's split between ok and `ServerError` depends on which calls the 16 failures land on; the run checks that every 503 was retried except the last of each failed call.

After every scenario the run checks that the server holds no connection and that the process has as many threads and file descriptors as before it started, and every thread must finish within 120 s or the run fails as a deadlock.

What the table shows:

- **Bounded retries.** No call reached the fake more than 3 times. A `retry-after` that would take a call's waiting past 30 s is not waited for.
- **No write sent twice.** A POST, PUT or DELETE reached the fake once after a 5xx, a hang or a reset. Only `retry: :always` repeats one.
- **The right error class** for each fault: `RateLimitError`, `ServerError`, `TimeoutError`, `ConnectionError`, and the base `Error` for a body that is not JSON.
- **Uploads stream.** 800 MB went over the socket (each 100 MB file twice, after a 429 rewound it) for under 8 MB of memory.
- **Several processes on one token.** Each process has its own limiter, so together they overrun the budget at first. The 429's `ratelimit-remaining: 0` and `ratelimit-reset` stop each process until the window ends, and `retry-after` brings the refused calls back; all 48 calls succeeded.

### Soak

`rake "stress[30]"` gives eight threads one client each, on their own tokens, and has them call GET, POST, PUT and DELETE in turn for 30 minutes while the faults take 10 s turns: a 5xx burst, slow answers, resets, malformed JSON, a 429 storm, hangs, then a healthy turn. Memory is sampled every 30 s. The soak fails on an outcome other than success or a documented error class, on more than 3 attempts per call, when fewer than half the calls succeed, or when memory grows by 30 MB or more between the 60 s sample and the end.

Recorded 2026-09-30 on Ruby 4.0.7, arm64-darwin25, on the code after the pre-1.0 review fixes. The test suite ran on the same machine for part of the half hour, so the call count is a floor, not a throughput figure:

| Calls | Outcomes | Attempts | Retries | RSS |
|---|---|---|---|---|
| 66,770 in 30 min | 66,153 ok, 340 `ServerError`, 130 `Error` (malformed), 79 `ConnectionError`, 68 `TimeoutError` | 67,268 | 498 | 53 MB after the first minute, 53 to 55 MB throughout, 55 MB at the end (+1.8 MB) |

The soak ends with the same leak checks as every scenario, and they passed.
