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

Nested keys are sorted, so Pennylane reordering a schema never shows as drift. A second run on the same day is byte-identical unless Pennylane changed a page in between.

`scopes` holds one group per security requirement. The groups are alternatives: any one group grants access. Operations are sorted by operationId with a plain byte sort, so the PascalCase `ValidateAccountingSupplierInvoice` comes first.

## Taking a new snapshot

```sh
bundle exec rake contract:snapshot
```

This reaches `pennylane.readme.io` (the docs site, not the API). It is not part of `bundle exec rake`, and the tests for the tool run offline against the fixtures in `test/fixtures/contract/`. A new snapshot lands only in a pull request together with the code that matches it.

## What is generated from it

Two files are generated from the latest dated snapshot. Never edit either by hand.

```sh
bundle exec rake contract:sync checklist
```

- `lib/pennylane_client/operations.rb` (`rake contract:sync`): the operation table, one `PennylaneClient::Operation` per operationId, sorted, one per line. A row holds the verb, path, whether it takes a `cursor` (paginated), the request body kind (`:json`, `:multipart` or `nil`), the one documented 2xx code, and the deprecated flag. The generator refuses an operation with an unknown content type or without exactly one 2xx response.
- [`CHECKLIST.md`](CHECKLIST.md) (`rake checklist`): one row per operation, grouped by Pennylane's tag, with `registered` (in the table), `named` (a behaviour test under `test/resources/` carries `# names: <operationId>`), `live` and the test that proves it.

`rake stale` is part of `bundle exec rake`. It regenerates both in memory and fails if the committed files differ. CI also regenerates them on disk and runs `git diff --exit-code`.
