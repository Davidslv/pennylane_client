# pennylane_client

An unofficial Ruby client for the [Pennylane](https://www.pennylane.com) Company API v2. Not affiliated with Pennylane.

> **Status: in development, not yet released.** The plan is in [proposal 0001](proposals/0001-pennylane-client-gem.md) and delivery is tracked in [Epic #1](https://github.com/Davidslv/pennylane_client/issues/1). Today `client.call(:operationId, **params)` works for every operation; the named methods (`client.customer_invoices...`), pagination, rate limiting and retries are still to come.

## Why

Pennylane publishes no official Ruby SDK, and the existing community gems predate the 2026 API changes. `pennylane_client` aims to:

- reach every one of the Company API v2's 177 live operations from its first release;
- give each operation a stable, hand-chosen Ruby name before 1.0;
- stay inside Pennylane's rate limit (25 requests per 5 seconds per token) across threads;
- never retry a request that has side effects;
- have zero runtime dependencies.

## Planned usage

```ruby
# Gemfile
gem "pennylane_client"
```

```ruby
require "pennylane_client"

client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))

client.customer_invoices.list(filter: [{ field: "status", operator: "eq", value: "draft" }])
      .each { |invoice| puts invoice[:invoice_number] }
client.customer_invoices.finalize(42)
client.call(:getCustomerInvoice, id: 42)   # any operation, by its Pennylane operationId
```

Responses are frozen Hashes with symbol keys, exactly as Pennylane sends them. Money stays a decimal string (`"230.32"`).

## Requirements

Ruby 3.3 or newer. No runtime dependencies.

## Documentation

- [Getting started](docs/getting-started.md)
- [Architecture](docs/architecture.md) and the [design diagram](docs/architecture/design-diagram.md)
- [How-to recipes](docs/how-to.md)
- [Domain language](CONTEXT.md)

## How it is built

This is a clean-room implementation: it is written only from Pennylane's public documentation and observed sandbox behaviour. See [CONTEXT.md](CONTEXT.md) for the rule and [AGENTS.md](AGENTS.md) for how it is enforced.

The maintainer has no Pennylane account, so no operation has been verified against a live sandbox yet. If you have one and want to help, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). `bundle exec rake` must stay green.

## Licence

MIT. See [LICENSE.txt](LICENSE.txt).
