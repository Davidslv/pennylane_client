# Getting started

> **Not yet released.** This guide describes the planned first release. Each section is filled in as the matching part of [Epic #1](https://github.com/Davidslv/pennylane_client/issues/1) lands.

## Install

```ruby
# Gemfile
gem "pennylane_client"
```

Ruby 3.3 or newer. No runtime dependencies.

## Get a token

Pennylane's Company API uses bearer tokens. A company admin on an Essential plan or higher creates one under **Settings > Connectivity > Developers**, choosing read-only or read-and-write, and an expiry. See Pennylane's guide: <https://pennylane.readme.io/docs/generating-my-api-token>.

## First call

```ruby
require "pennylane_client"

client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))
client.call(:getMe)
```

`token:` also takes anything that responds to `#call` and returns the current token, e.g. `token: -> { TokenStore.current }`. It is asked once per call. The client never refreshes a token itself.

Clients are cheap to build. They share one connection pool and, per token, one rate-limit budget.

`call` takes any Pennylane operationId from [the checklist](api/CHECKLIST.md) and its parameters as keywords. Path parameters fill the URL; the rest is the JSON body when the operation takes one, and the query string otherwise:

```ruby
client.call(:getJournal, id: 42)
client.call(:getJournals, filter: [{ field: "code", operator: "eq", value: "HA" }])
client.call(:postJournals, code: "HA", label: "Achats")
client.call(:markAsPaidCustomerInvoice, id: 42)   # => true (204, no body)
```

A few operations take a JSON array as their body. Pass it as the second argument:

```ruby
client.call(:putCustomerCategories, [{ id: 3, weight: "1" }], customer_id: 9)
```

## Named methods

Operations marked `named` in [the checklist](api/CHECKLIST.md) also have a Ruby method on a resource. The name stays the same if Pennylane renames the operationId:

```ruby
invoices = client.customer_invoices

invoices.list(filter: [{ field: "status", operator: "eq", value: "draft" }]).each { |invoice| ... }
invoice = invoices.create(customer_id: 7, date: Date.today, deadline: Date.today + 30, draft: true,
                          invoice_lines: [{ label: "Audit", quantity: 1, raw_currency_unit_price: "500", unit: "day",
                                            vat_rate: "FR_200" }])
invoices.finalize(invoice[:id])
invoices.send_by_email(invoice[:id])
```

Attributes go to Pennylane as you pass them. Lists return every item lazily, as `client.paginate` does. The full list of methods is in `lib/pennylane_client/resources/` and `sig/pennylane_client/resources.rbs`; the how-to covers the ones you would not guess, for [customer invoices](how-to.md#work-with-customer-invoices), [customers](how-to.md#work-with-customers), [supplier invoices and suppliers](how-to.md#work-with-supplier-invoices-and-suppliers), [mandates](how-to.md#work-with-mandates), [transactions and bank accounts](how-to.md#work-with-transactions-and-bank-accounts), and [quotes and commercial documents](how-to.md#work-with-quotes-and-commercial-documents).

## When it fails

Every error is a `PennylaneClient::Error` with `#status`, `#code`, `#details` and `#body`:

| Class | When |
|---|---|
| `ValidationError` | 400, 422 |
| `AuthenticationError` | 401 |
| `PermissionError` | 403 |
| `NotFoundError` | 404 |
| `ConflictError` | 409 |
| `RateLimitError` | 429; `#retry_after` in seconds |
| `ServerError` | 5xx |
| `ConnectionError`, `TimeoutError` | no response arrived |

An unknown operationId raises `PennylaneClient::UnknownOperationError`, an `ArgumentError`.

Before raising, the client retries what is safe to repeat: a 429 for any request, after Pennylane's `retry-after`; a 5xx or no response for a GET only. A POST, PUT or DELETE that fails with a 5xx or a timeout is not sent again, because Pennylane may already have applied it. See [the how-to](how-to.md#retries-and-the-rate-limit).

## What comes back

Responses are deep-frozen Hashes with symbol keys, exactly as Pennylane sends them. Money is a decimal string and dates are ISO 8601 strings:

```ruby
BigDecimal(invoice[:amount])   # "230.32" -> 0.23032e3
Date.iso8601(invoice[:date])
```
