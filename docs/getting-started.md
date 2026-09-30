# Getting started

> **Version 0.1.0, pre-1.0.** Method names may still change before 1.0.0.

This guide goes from a token to a first real workflow: create a customer, invoice them, find your drafts, attach a file, and handle what goes wrong. Every example runs in the test suite, one after the other, against the answers Pennylane documents.

## Install

<!-- not run: a Gemfile line -->
```ruby
# Gemfile
gem "pennylane_client", "~> 0.1"
```

Or `gem install pennylane_client`. Ruby 3.3 or newer. No runtime dependencies.

## Get a token

The Company API uses bearer tokens. A company admin on an Essential plan or higher creates one in Pennylane under **Settings > Connectivity > Developers**, choosing read-only or read and write, and an expiry. See Pennylane's guide: <https://pennylane.readme.io/docs/generating-my-api-token>.

Keep the token out of your code. The examples read it from `PENNYLANE_TOKEN`.

## Build a client and check the token

<!-- example -->
```ruby
require "pennylane_client"

client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))

me = client.users.me
me[:company][:name]   # => "Pennylane"
me[:scopes]           # => ["customer_invoices", "suppliers"]
```

`users.me` says which company the token belongs to and what it may do. A token without the scope an operation needs gets a `PermissionError`.

Clients are cheap to build. They share the same connections, one per thread or fiber, and, per token, one rate-limit budget per process. A client is safe to share between threads, and a forking server such as Puma in cluster mode needs no setup ([forking web servers](how-to.md#forking-web-servers-and-job-runners)).

## Two ways to call an operation

An operation is one HTTP method on one path, such as `GET /api/external/v2/customer_invoices/{id}`. Pennylane gives each one an operationId (`getCustomerInvoice`). Every live operation has a named method on a resource, and `client.call` takes any operationId:

<!-- example continued -->
```ruby
client.customer_invoices.find(42)
client.call(:getCustomerInvoice, id: 42)   # the same request
```

Prefer the named method. Its name stays the same if Pennylane renames the operationId, and it checks its required arguments before sending anything. `client.call` is there for an operation you want to reach by the name in Pennylane's reference.

With `call`, path parameters fill the URL. The other keywords are the JSON body when the operation takes one, and the query string otherwise. A few operations take a JSON array as their body; pass it as the second argument:

<!-- example continued -->
```ruby
client.call(:putCustomerCategories, [{ id: 426, weight: "1" }], customer_id: 42)
```

## The argument rule

Named methods take their arguments in one of three ways:

- **Creates, imports and updates take `**attributes`**: `create`, `create_company`, `create_from_quote`, `import`, `update`, `update_imported` and the like. The client checks none of them. Pennylane validates the fields, and a missing one raises `ValidationError`.
- **Actions take their required fields as keywords**, so a missing one raises `ArgumentError` before anything is sent: `update_payment_status(42, payment_status: "paid")`, `match_transaction(42, transaction_id: 9)`, `link_credit_note(42, credit_note_id: 43)`, `letter(lines, unbalanced_lettering_strategy: "none")`. The status changes (`update_status`, `update_payment_status`, `update_e_invoice_status`) are actions.
- **`customers.create(customer_type:, **attributes)` is the one exception.** `customer_type:` picks which kind of customer Pennylane creates, and so which fields it expects. Prefer `create_company` and `create_individual`.

Ids are positional: `find(42)`, `update(42, ...)`, `delete_contact(7, 3)`. A keyword naming one raises `ArgumentError` rather than change which record is written, so `products.update(1, id: 2)` raises. The id of a linked record is a keyword named after Pennylane's field (`transaction_id:`, `credit_note_id:`).

Every named write also takes `retry:`; see [retries](how-to.md#retry-a-request).

## Create a customer

Pennylane keeps company and individual customers apart. A company customer needs a `name:` and a `billing_address:`:

<!-- example continued -->
```ruby
acme = client.customers.create_company(
  name: "Acme",
  billing_address: { address: "8 rue de la paix", postal_code: "75002", city: "Paris", country_alpha2: "FR" },
  emails: ["billing@acme.example"],
  payment_conditions: "30_days"
)
acme[:id]   # => 42
```

## Create and finalize a customer invoice

Create the invoice as a draft, check it, then finalize it. Finalizing gives it a number from the company's invoice numbering and makes it final:

<!-- example continued -->
```ruby
invoice = client.customer_invoices.create(
  customer_id: acme[:id],
  date: Date.today,
  deadline: Date.today + 30,
  draft: true,
  invoice_lines: [
    { label: "Audit", quantity: 2, unit: "day", raw_currency_unit_price: "450.00", vat_rate: "FR_200" }
  ]
)

invoice = client.customer_invoices.finalize(invoice[:id])
invoice[:invoice_number]   # => "F20230001"

client.customer_invoices.send_by_email(invoice[:id])   # => true
```

`Date.today` is sent as `"2026-09-30"`. A `BigDecimal` amount is sent as a plain decimal String. Numbers are not: Pennylane refuses a numeric amount, so pass amounts as Strings or BigDecimals.

`send_by_email` raises `ConflictError` while Pennylane is still generating the PDF. Try again a little later.

## Find your draft invoices

Every `list` returns the items lazily and fetches the next page only when you read past the current one. `filter:` takes the conditions as an Array of Hashes, in the fields each operation documents:

<!-- example continued -->
```ruby
drafts = [{ field: "draft", operator: "eq", value: "true" },
          { field: "date", operator: "gteq", value: "2026-01-01" }]

client.customer_invoices.list(filter: drafts, sort: "-date").each do |draft|
  puts "#{draft[:label]}: #{draft[:currency_amount]} #{draft[:currency]}"
end

client.customer_invoices.list(filter: drafts).first(10)   # one request
```

The how-to has more on [lists](how-to.md#walk-a-list) and [filters](how-to.md#filter-and-sort-a-list).

## Attach a file

Pass a `Pathname`, a `File` or an IO. A file on disk is streamed, not read into memory:

<!-- example continued -->
```ruby
client.customer_invoices.upload_appendix(invoice[:id], Pathname("timesheet.pdf"))

attachment = client.file_attachments.upload(Pathname("receipt.pdf"))
attachment[:id]   # use it as file_attachment_id: when importing an invoice
```

The filename comes from the path and the content type from the extension. See [upload a file](how-to.md#upload-a-file) to set either yourself, and [upload a file you built in memory](how-to.md#upload-a-file-you-built-in-memory) for a PDF you generate.

## Handle errors

Every error the client raises about a request is a `PennylaneClient::Error`. The subclass follows the HTTP status, and `details` carries Pennylane's explanation when it sends one:

<!-- example continued validation_error -->
```ruby
begin
  client.customer_invoices.create(date: Date.today, deadline: Date.today + 30, invoice_lines: [])
rescue PennylaneClient::ValidationError => e
  e.status    # => 422
  e.code      # => "unprocessable_entity"
  e.message   # => "422 unprocessable_entity: Missing required field: customer_id"
  e.details   # => { field: "customer_id", issue: "is required" }
end
```

| Class | When | What to do |
|---|---|---|
| `ValidationError` | 400, 422 | Fix the payload; read `details`. |
| `AuthenticationError` | 401 | The token is missing, invalid or expired. The client never refreshes it. |
| `PermissionError` | 403 | The token lacks the scope, or the company lacks the feature. |
| `NotFoundError` | 404 | The record does not exist or belongs to another company. |
| `ConflictError` | 409 | A duplicate import, or a PDF still being generated. Not retried. |
| `RateLimitError` | 429 | Already retried after `retry-after`; `retry_after` says how long to wait. |
| `ServerError` | 5xx | Already retried for a GET. A write is not sent twice. |
| `ConnectionError`, `TimeoutError` | no response arrived | As for `ServerError`. |
| `ExportError` | an export failed or was not ready in time | `export` has the export's id. |

A 2xx body that is not JSON, or not valid UTF-8, raises the base `Error`. An unknown operationId raises `PennylaneClient::UnknownOperationError`, an `ArgumentError`, as does a missing required keyword.

Before raising, the client retries what is safe to repeat: a 429 for any request, after Pennylane's `retry-after`, and a 5xx or no response for a GET only. A POST, PUT or DELETE that fails with a 5xx or a timeout is not sent again, because Pennylane may already have applied it. [Retry a request](how-to.md#retry-a-request) says how to opt in.

## Read money and dates

Responses are deep-frozen Hashes with symbol keys, exactly as Pennylane sends them. Money is a decimal String and dates are ISO 8601 Strings. Convert them when you need to calculate:

<!-- example continued -->
```ruby
require "bigdecimal"
require "date"

BigDecimal(invoice[:amount])                  # "230.32" -> 0.23032e3
BigDecimal(invoice[:currency_amount_before_tax]) + BigDecimal(invoice[:currency_tax])
Date.iso8601(invoice[:date])                  # "2023-08-30" -> #<Date: 2023-08-30>
Time.iso8601(invoice[:created_at])            # "2023-08-30T10:08:08.146343Z"
```

On Ruby 3.4 and newer `bigdecimal` is a bundled gem, so add `gem "bigdecimal"` to your own Gemfile. The client never requires it.

A response is frozen, nested Hashes and Arrays included. `invoice.merge(label: "Audit")` gives you a changed copy.

## Next

- [How-to recipes](how-to.md): pagination, retries, rate limits, uploads, webhooks, exports, changelogs, testing your app, Rails.
- [The checklist](api/CHECKLIST.md): every operation, its operationId and whether it is live-verified.
- [Stability](../README.md#stability): which methods are Experimental.
