# Architecture

How the gem is put together, and why. Written for someone about to change the code. If the code and this document disagree, the code wins and this document has a bug.

> The gem is being built. This document describes what exists today and points to the plan for the rest. The full design is in [proposal 0001](../proposals/0001-pennylane-client-gem.md) and drawn in the [design diagram](architecture/design-diagram.md).

## What exists today

| Component | File | Role |
|---|---|---|
| `PennylaneClient` | `lib/pennylane_client.rb` | The namespace. |
| `PennylaneClient::VERSION` | `lib/pennylane_client/version.rb` | Gem version. |

## Planned components

From the design diagram, in the order they are built (Epic #1):

1. **Contract tooling (dev time).** A snapshot of Pennylane's published operations, a generated operation table, and a generated checklist.
2. **Runtime core.** `Client` (wiring only), `Operation`, `Registry`, `Executor`, the error hierarchy, the request encoder, `Transport`.
3. **Middleware.** `Auth` (token provider), `RateLimit` (25 requests per 5 seconds per token), `Retry` (429 for any method, 5xx for GET only).
4. **Pagination and uploads.** Cursor pagination that re-sends filters on every page; multipart uploads.
5. **Resources.** Hand-written one-liner methods per resource group.

## Design rationale

The reasoning behind each choice is recorded as decisions D1 to D8 in [proposal 0001](../proposals/0001-pennylane-client-gem.md). The short version:

- **Generated table, hand-written names (D3).** Every operation is reachable from the snapshot on day one; Ruby names are chosen by a person and survive Pennylane renaming an operationId.
- **Never retry side effects (D5).** Pennylane does not enforce idempotency on creates.
- **Raw values (D6).** Money stays a string, so no field list drifts and no `bigdecimal` dependency is needed.

## Where this design would strain

Honest limits, known before the code exists:

- **Multi-process deployments share one token's budget.** The limiter is per process. Header self-correction and 429 retries absorb the overflow; a shared store needs a limiter you inject yourself.
- **No live verification yet.** The maintainer has no Pennylane account, so behaviour is checked against the documentation, not a sandbox.
- **Responses are untyped.** Callers convert money and dates themselves.
