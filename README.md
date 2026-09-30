# pennylane_client

An unofficial Ruby client for the [Pennylane](https://www.pennylane.com) Company API v2. Not affiliated with Pennylane.

> **Status: 0.1.0, pre-1.0.** Method names may still change before 1.0.0. Every live operation has a named method, and `client.call` reaches every operation by its Pennylane operationId. The plan is in [proposal 0001](proposals/0001-pennylane-client-gem.md) and delivery is tracked in [Epic #1](https://github.com/Davidslv/pennylane_client/issues/1).

## Install

<!-- not run: a Gemfile line -->
```ruby
# Gemfile
gem "pennylane_client", "~> 0.1"
```

Or `gem install pennylane_client`. Ruby 3.3 or newer. No runtime dependencies.

## Quick start

A company admin creates a token in Pennylane under **Settings > Connectivity > Developers**. Then:

<!-- example -->
```ruby
require "pennylane_client"

client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))

client.users.me[:company][:name]                   # => "Pennylane"

drafts = [{ field: "draft", operator: "eq", value: "true" }]
client.customer_invoices.list(filter: drafts).each do |invoice|
  puts "#{invoice[:invoice_number]} #{invoice[:amount]}"
end
client.call(:getCustomerInvoice, id: 42)           # any operation, by its operationId
```

[Getting started](docs/getting-started.md) goes from here to a first real workflow.

## What you get

- **Every operation.** `client.call(:operationId, **params)` reaches all 177 live operations of the Company API v2 from the committed contract snapshot.
- **A named method for each one.** `client.customer_invoices.finalize(42)`, `client.ledger_entry_lines.letter(...)`: 177 Named operations, each with a hand-chosen name that stays the same if Pennylane renames the operationId.
- **The rate limit.** 25 requests per 5 seconds per token, shared by every client and thread in the process, corrected from Pennylane's rate-limit headers. Bring your own limiter to share it across processes.
- **Safe retries.** A 429 is retried for any request. A 5xx or a timeout is retried for a GET only. A write that may have reached Pennylane is not sent again unless you pass `retry: :always`.
- **Pagination.** Every list returns its items lazily and follows Pennylane's cursor, sending your `filter` and `sort` again on each page.
- **Uploads.** Files stream from disk as multipart, so a 100 MB file does not load 100 MB into memory.
- **Webhooks.** `PennylaneClient::Webhook.verify!` checks a delivery's signature and timestamp.
- **Zero dependencies.** The standard library only.

Responses are deep-frozen Hashes with symbol keys, exactly as Pennylane sends them. Money is a decimal String (`"230.32"`) and dates are ISO 8601 Strings.

## Resource groups

One accessor per resource group, following Pennylane's grouping. Each line below is one example:

<!-- example -->
```ruby
# Sales
client.customer_invoices.finalize(42)
client.customers.create_company(name: "Acme", billing_address: { address: "8 rue de la paix", postal_code: "75002",
                                                                 city: "Paris", country_alpha2: "FR" })
client.quotes.update_status(42, status: "accepted")
client.commercial_documents.find(42)
client.customer_invoice_templates.list.to_a
client.numberings.list.to_a
client.billing_subscriptions.list(filter: [{ field: "status", operator: "eq", value: "in_progress" }]).first
client.products.list(filter: [{ field: "reference", operator: "eq", value: "CONS-DAY" }]).first

# Purchases
client.supplier_invoices.update_payment_status(42, payment_status: "paid")
client.suppliers.find(42)
client.purchase_requests.find(42)

# Banking and payments
client.transactions.matched_invoices(42).to_a
client.bank_accounts.list.to_a
client.bank_establishments.list.first
client.sepa_mandates.find(42)
client.gocardless_mandates.cancel(42)
client.pro_account_mandates.migration_candidates.first

# Accounting
client.journals.list.to_a
client.ledger_accounts.list(filter: [{ field: "number", operator: "start_with", value: "512" }]).first
client.ledger_entries.lines(42).to_a
client.ledger_entry_lines.lettered_lines(42).to_a
client.fiscal_years.list.to_a
client.trial_balance.list(period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 12, 31)).first
client.categories.list.first
client.category_groups.categories(42).to_a
client.file_attachments.upload(Pathname("receipt.pdf"))
client.exports.create_fec(period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 6, 30))

# Sync and account
client.changelogs.customer_invoices(since: Time.now - 3600).to_a
client.webhook_subscriptions.list.to_a
client.users.me
client.company.features
client.pa_registrations.list.to_a
```

The [how-to](docs/how-to.md) has a section per resource group for the methods you would not guess. The full list is in `sig/pennylane_client/resources.rbs`, and the [checklist](docs/api/CHECKLIST.md) maps each operationId to its method.

## Errors

Every error the client raises about a request is a `PennylaneClient::Error`, with `status`, `code`, `details`, `body` and `headers`. The subclass follows the HTTP status:

| Class | When |
|---|---|
| `ValidationError` | 400, 422 |
| `AuthenticationError` | 401 |
| `PermissionError` | 403 |
| `NotFoundError` | 404 |
| `ConflictError` | 409 |
| `RateLimitError` | 429; `retry_after` in seconds |
| `ServerError` | 5xx |
| `ConnectionError`, `TimeoutError` | no response arrived |
| `ExportError` | an export failed or was not ready in time |
| `SignatureError` | a webhook delivery failed verification |

An unknown operationId raises `PennylaneClient::UnknownOperationError`, an `ArgumentError`. A missing required keyword raises `ArgumentError` before anything is sent. See [handle errors](docs/getting-started.md#handle-errors).

## Configuration

<!-- example -->
```ruby
require "logger"

PennylaneClient.configure do |config|
  config.logger = Logger.new($stdout)                      # one line per request, retry and wait
  config.on_request = ->(event) { puts event[:duration] }  # one frozen event Hash per request
end

client = PennylaneClient.new(
  token: ENV.fetch("PENNYLANE_TOKEN"),  # a String, or anything with #call that returns one
  max_retry_wait: 10,                   # seconds one call may spend waiting to retry (default 30)
  transport: PennylaneClient::NetHttpTransport.new(read_timeout: 60)
)
```

`PennylaneClient.new` also takes `logger:` and `on_request:` to override the configuration for one client, and `limiters:` to replace the rate limiter. A client reads the configuration when it is built. The [how-to](docs/how-to.md) covers each option.

## Public API

This list is the public API: what [Semantic Versioning](#stability) covers. Everything else under `PennylaneClient` is tagged `@api private` in its documentation and may change in any release.

<!-- public-api: checked against the code by test/public_api_test.rb -->
- `PennylaneClient.new(token:, ...)`, which returns a `PennylaneClient::Client`, and `PennylaneClient.configure`, which yields the `PennylaneClient::Configuration` (`logger`, `on_request`).
- `PennylaneClient::Client`: `call`, `paginate`, `pages`, and one accessor per resource group (`customer_invoices`, `customers`, `supplier_invoices` and the rest listed under [Resource groups](#resource-groups)).
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

## Documentation

- [Getting started](docs/getting-started.md): from a token to a first workflow.
- [How-to recipes](docs/how-to.md): pagination, filters, retries, rate limits, uploads, webhooks, exports, changelogs, testing, Rails.
- [Architecture](docs/architecture.md) and the [design diagram](docs/architecture/design-diagram.md).
- [Performance](docs/performance.md): load and stress results against a local fake.
- [Domain language](CONTEXT.md).

Every Ruby example in this README, the getting-started guide and the how-to runs in the test suite against the contract snapshot (`test/docs_examples_test.rb`).

## How it is built

This is a clean-room implementation: it is written only from Pennylane's public documentation and observed sandbox behaviour. See [CONTEXT.md](CONTEXT.md) for the rule and [AGENTS.md](AGENTS.md) for how it is enforced.

The gem is written against a Contract snapshot: a dated copy of Pennylane's published API definition in `docs/api/contract/`. The operation table is generated from it, and a weekly job opens an issue when Pennylane publishes something the snapshot does not match.

The maintainer has no Pennylane account. Operations are verified live by contributors who run `rake smoke` against their own sandbox.

<!-- live-count: generated by `rake checklist`, do not edit -->
Live-verified against a Pennylane sandbox: **0 of 177** live operations. The [checklist](docs/api/CHECKLIST.md) lists which, and [CONTRIBUTING.md](CONTRIBUTING.md#verifying-against-a-real-pennylane-sandbox) says how to add to it.
<!-- /live-count -->

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). `bundle exec rake` must stay green.

## Licence

MIT. See [LICENSE.txt](LICENSE.txt).
