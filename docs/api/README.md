# The contract snapshot

`docs/api/contract/<date>/` is a dated copy of the Pennylane Company API v2 as published on that day. Everything the gem says about completeness is measured against the latest one. It is machine-generated: never edit it by hand.

## What is in a snapshot

- `operations.json`: every operation, sorted by operationId. Each record holds `operation_id`, `method`, `path`, `summary`, `description`, `tags`, `scopes`, `deprecated`, `parameters`, `request_body`, `responses` and `source_url`. A `summary` block at the top gives the operation, path and method counts and lists deprecated operations.
- `guides/`: the guides the gem's behaviour depends on (rate limiting, cursor pagination, errors, webhooks, OAuth, the 2026 migration). Each file starts with its source URL and retrieval date.

Dated folders are kept, so "what did 0.3.0 target?" always has an answer.

## Where it comes from

`tools/snapshot_contract.rb` reads two sources and requires them to agree:

1. The documented surface: `https://pennylane.readme.io/llms.txt`, then every `/reference/*.md` page it lists, then the OpenAPI fragment embedded in each page. This is the primary source.
2. `https://pennylane.readme.io/openapi/accounting.json`, the full spec. The docs do not link to it, so it is a cross-check only. If the operation sets differ the tool fails and prints both sides. If the URL is gone it warns and carries on.

Nested keys are sorted, so Pennylane reordering a schema never shows as drift. A second run on the same day is byte-identical.

## Taking a new snapshot

```sh
bundle exec rake contract:snapshot
```

This reaches `pennylane.readme.io` (the docs site, not the API). It is not part of `bundle exec rake`, and the tests for the tool run offline against the fixtures in `test/fixtures/contract/`. A new snapshot lands only in a pull request together with the code that matches it.
