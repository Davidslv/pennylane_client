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

## What comes back

Responses are deep-frozen Hashes with symbol keys, exactly as Pennylane sends them. Money is a decimal string and dates are ISO 8601 strings:

```ruby
BigDecimal(invoice[:amount])   # "230.32" -> 0.23032e3
Date.iso8601(invoice[:date])
```
