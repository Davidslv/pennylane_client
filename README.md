# pennylane_client

An unofficial Ruby client for the [Pennylane](https://www.pennylane.com) Company API v2. Not affiliated with Pennylane.

> **Status: 0.1.0, pre-1.0.** Method names may still change before 1.0.0. The plan is in [proposal 0001](proposals/0001-pennylane-client-gem.md) and delivery is tracked in [Epic #1](https://github.com/Davidslv/pennylane_client/issues/1). `client.call(:operationId, **params)` works for every operation, inside the rate limit and with safe retries; `client.paginate` walks any list, and uploads stream from disk. Load and stress results against a local fake are in [docs/performance.md](docs/performance.md). Every live operation has a named method (`client.customer_invoices...`, `client.customers...`, `client.supplier_invoices...`, `client.suppliers...`, `client.sepa_mandates...`, `client.gocardless_mandates...`, `client.pro_account_mandates...`, `client.transactions...`, `client.bank_accounts...`, `client.bank_establishments...`, `client.quotes...`, `client.commercial_documents...`, `client.customer_invoice_templates...`, `client.numberings...`, `client.journals...`, `client.ledger_accounts...`, `client.ledger_entries...`, `client.ledger_entry_lines...`, `client.fiscal_years...`, `client.trial_balance...`, `client.file_attachments...`, `client.categories...`, `client.category_groups...`, `client.products...`, `client.changelogs...`, `client.exports...`, `client.billing_subscriptions...`, `client.purchase_requests...`, `client.webhook_subscriptions...`, `client.users.me`, `client.company.features`, `client.pa_registrations.list`).

## Why

Pennylane publishes no official Ruby SDK, and the existing community gems predate the 2026 API changes. `pennylane_client` aims to:

- reach every one of the Company API v2's 177 live operations from its first release;
- give each operation a stable, hand-chosen Ruby name before 1.0;
- stay inside Pennylane's rate limit (25 requests per 5 seconds per token) across threads;
- never retry a request that has side effects;
- have zero runtime dependencies.

## Usage

```ruby
# Gemfile
gem "pennylane_client", "~> 0.1"
```

Or `gem install pennylane_client`.

```ruby
require "pennylane_client"

client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))

client.customer_invoices.list(filter: [{ field: "status", operator: "eq", value: "draft" }])
      .each { |invoice| puts invoice[:invoice_number] }
client.customer_invoices.finalize(42)
client.customer_invoices.send_by_email(42)
client.customers.find(7)
client.supplier_invoices.update_payment_status(43, payment_status: "paid")
client.products.find(3)
client.call(:getMe)   # any operation, by its Pennylane operationId
```

A write is never sent twice after a 5xx or a timeout. When one is safe to repeat, pass `retry: :always` to its named method or to `client.call`; see [retries](docs/how-to.md#retries-and-the-rate-limit).

Operations with a Ruby name are marked `named` in the [checklist](docs/api/CHECKLIST.md). Every other operation is reachable through `client.call` until it gets one.

Responses are frozen Hashes with symbol keys, exactly as Pennylane sends them. Money stays a decimal string (`"230.32"`).

### Inbound webhooks

```ruby
event = PennylaneClient::Webhook.verify!(raw_body, headers["X-Pennylane-Signature"],
                                         secret: ENV.fetch("PENNYLANE_WEBHOOK_SECRET"))
event[:id]     # the delivery id
event[:event]  # "customer_invoice.e_invoicing_status_updated"
```

`verify!` checks the HMAC-SHA256 signature in constant time, rejects a timestamp more than 300 seconds from now (`tolerance:`), and returns the deep-frozen event. A bad delivery raises `PennylaneClient::SignatureError`; a blank secret raises `ArgumentError`. Pass the raw body bytes, not re-serialised JSON.

Pennylane delivers at least once and in no particular order. De-duplicate on the delivery `id` and make your handler idempotent; storing seen ids is up to you. See [how-to](docs/how-to.md#verify-an-inbound-webhook).

## Public API

This list is the public API: what [Semantic Versioning](#stability) covers. Everything else under `PennylaneClient` is tagged `@api private` in its documentation and may change in any release.

<!-- public-api: checked against the code by test/public_api_test.rb -->
- `PennylaneClient.new(token:, ...)`, which returns a `PennylaneClient::Client`, and `PennylaneClient.configure`, which yields the `PennylaneClient::Configuration` (`logger`, `on_request`).
- `PennylaneClient::Client`: `call`, `paginate`, `pages`, and one accessor per resource group (`customer_invoices`, `customers`, `supplier_invoices` and the rest listed in the status line above).
- Every public method of the `PennylaneClient::Resources` classes those accessors return: the named methods. The Experimental ones are listed under Stability.
- The errors: `PennylaneClient::Error` (`status`, `body`, `headers`, `details`) and its subclasses `PennylaneClient::AuthenticationError`, `PennylaneClient::PermissionError`, `PennylaneClient::NotFoundError`, `PennylaneClient::ConflictError`, `PennylaneClient::ValidationError`, `PennylaneClient::RateLimitError`, `PennylaneClient::ServerError`, `PennylaneClient::ConnectionError`, `PennylaneClient::TimeoutError`, `PennylaneClient::ExportError` and `PennylaneClient::SignatureError`; and `PennylaneClient::UnknownOperationError`, an `ArgumentError`.
- `PennylaneClient::Webhook.verify!`.
- `PennylaneClient::Upload`, to set a file's name or content type.
- `PennylaneClient::LimiterRegistry` (`new(idle_after:) { |key| limiter }`, `fetch`, `default`) and the limiter interface: `acquire` waits for a call and returns the seconds waited, `update(remaining:, reset_at:)` takes the rate-limit headers, and `idle?` is optional.
- The transport interface: anything with `call(request)` that returns a `PennylaneClient::Response` (`status`, `headers` with lower-case names, `body`), raises `ConnectionError` or `TimeoutError` when no answer arrives, and never raises for an HTTP status. It is given a `PennylaneClient::Request` (`verb`, `url`, `headers`, `body`, `operation_id`, `retry_policy`); an upload's `body` responds to `read`, `rewind` and `size`.
- `PennylaneClient::NetHttpTransport`, the default transport: `new(open_timeout: 5, read_timeout: 30, write_timeout: 30, upload_timeout: 300, keep_alive_timeout: 10)`, `default` and `close`.
- `PennylaneClient::VERSION`.
<!-- /public-api -->

## Stability

From 1.0.0 the gem follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html), with one exception: Experimental APIs may change in a minor release. An Experimental method wraps an operation, or an input, that Pennylane itself marks Hidden, alpha or beta, so the gem cannot promise more than Pennylane does. Each one carries `@note Experimental` in its documentation. Pin a minor version (`"~> 1.2.0"`) if you depend on one.

Experimental:

<!-- experimental: checked against the code by test/stability_test.rb -->
- `client.customers.create`: `postCustomer`, which Pennylane tags Hidden. `create_company` and `create_individual` are stable.
- `client.customer_invoices.mark_installment_as_paid`: Hidden and alpha at Pennylane.
- `client.webhook_subscriptions.list`, `client.webhook_subscriptions.find`, `client.webhook_subscriptions.create`, `client.webhook_subscriptions.update` and `client.webhook_subscriptions.delete`: webhooks are beta at Pennylane. `PennylaneClient::Webhook.verify!` is stable.
- `client.customer_invoices.import_e_invoice` and `client.supplier_invoices.import_e_invoice` with a UBL or CII XML file, which Pennylane calls alpha. A Factur-X PDF is stable.
<!-- /experimental -->

## Requirements

Ruby 3.3 or newer. No runtime dependencies.

## Documentation

- [Getting started](docs/getting-started.md)
- [Architecture](docs/architecture.md) and the [design diagram](docs/architecture/design-diagram.md)
- [How-to recipes](docs/how-to.md)
- [Domain language](CONTEXT.md)

## How it is built

This is a clean-room implementation: it is written only from Pennylane's public documentation and observed sandbox behaviour. See [CONTEXT.md](CONTEXT.md) for the rule and [AGENTS.md](AGENTS.md) for how it is enforced.

The maintainer has no Pennylane account. Operations are verified live by contributors who run `rake smoke` against their own sandbox.

<!-- live-count: generated by `rake checklist`, do not edit -->
Live-verified against a Pennylane sandbox: **0 of 177** live operations. The [checklist](docs/api/CHECKLIST.md) lists which, and [CONTRIBUTING.md](CONTRIBUTING.md#verifying-against-a-real-pennylane-sandbox) says how to add to it.
<!-- /live-count -->

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). `bundle exec rake` must stay green.

## Licence

MIT. See [LICENSE.txt](LICENSE.txt).
