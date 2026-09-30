# pennylane_client domain language

The terms that mean something specific when building and maintaining this gem. When conversation and this glossary disagree, the glossary wins.

## Operation

One HTTP method on one path in the Pennylane API, e.g. `GET /api/external/v2/customer_invoices`.

- The unit of the checklist and of "complete". The Company API v2 had 178 Operations on 2026-09-29.
- Distinct from Endpoint: people say "endpoint" loosely for a path, and one path can carry several Operations (a list GET and a create POST). Count and track Operations, never "endpoints".
- Each Operation has a stable `operationId` from Pennylane's spec (e.g. `getCustomerInvoices`). That is its identity in the checklist.

## Registered operation

An Operation that appears in the gem's operation table, so a caller can reach it through `call` by its operationId.

- Every live Operation in the committed Contract snapshot is registered from day one, because the table is generated from the snapshot.
- Registered says nothing about correctness or naming. It means only "reachable".

## Named operation

A Registered operation that also has a stable, hand-chosen Ruby method (e.g. `customer_invoices.finalize`) and a behaviour test that names its operationId and sends it.

- The Ruby name is a promise to callers. It survives Pennylane renaming the operationId.
- "Done" in the checklist means Named. The gem reaches 1.0 when every live Operation is Named.
- Distinct from Registered: an Operation can be Registered for months before it is Named.

## Resource group

A family of Operations about one kind of thing, e.g. Customer Invoices, Ledger Entries, Webhooks.

- Follows Pennylane's own grouping in their reference docs.
- One Resource group becomes one sub-issue in the delivery Epic.

## Contract snapshot

A dated, committed copy of Pennylane's published API definition that the gem is written against.

- Machine-generated from Pennylane's docs. Never edited by hand.
- The gem is "complete" relative to a Contract snapshot, not relative to the live API.
- Distinct from Drift: Drift is the difference between the committed snapshot and what Pennylane publishes today.

## Clean room

The rule that the gem is built only from Pennylane's public documentation and observed sandbox behaviour.

- Allowed: Pennylane's reference pages, guides, changelog, published OpenAPI definitions, and responses seen from the sandbox.
- Forbidden: the source, README or tests of any other Pennylane client in any language, read by a person or an agent working on the gem.
- When the docs contradict each other, the sandbox settles it and the choice is recorded. Another client's behaviour never settles it.

## Drift

A difference between the committed Contract snapshot and the API Pennylane currently publishes.

- Detected by an automated job that regenerates the snapshot and diffs it.
- New Operations, removed Operations, changed parameters or fields, and newly deprecated Operations all count.
