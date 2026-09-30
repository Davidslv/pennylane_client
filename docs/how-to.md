# How-to recipes

Task-oriented recipes. Each is added when the feature it describes ships.

## Convert money and dates

Pennylane sends amounts as decimal strings and dates as ISO 8601 strings. The gem returns them unchanged:

```ruby
require "bigdecimal"
require "date"

BigDecimal(invoice[:amount])
Date.iso8601(invoice[:date])
```

On Ruby 3.4 and newer `bigdecimal` is a bundled gem, so add `gem "bigdecimal"` to your own Gemfile. The client itself never requires it.

Send amounts as strings too. Pennylane rejects numeric amounts with a 400. The client converts a `BigDecimal`, `Date` or `Time` you pass for you:

```ruby
client.call(:createTransaction, bank_account_id: 1, label: "Rent",
                                amount: BigDecimal("12.50"), date: Date.today)   # sends "12.5" and "2026-09-30"
```

## Log requests and collect metrics

```ruby
PennylaneClient.configure do |config|
  config.logger = Rails.logger
  config.on_request = ->(event) { StatsD.measure("pennylane.request", event[:duration]) }
end
```

Configure before building clients; a client reads the configuration when it is built. `PennylaneClient.new(token:, logger:, on_request:)` overrides it per client.

Each attempt sent to Pennylane, each retry and each rate-limit wait writes one line and fires one event, a frozen Hash. `type` says which:

```ruby
{ type: :request, operation_id: :getMe, method: "GET", path: "/api/external/v2/me", status: 200, error: nil, duration: 84.2 }
{ type: :retry, operation_id: :getMe, method: "GET", path: "/api/external/v2/me", attempt: 2, wait: 0.3, status: 503, error: nil }
{ type: :wait, operation_id: :getMe, method: "GET", path: "/api/external/v2/me", wait: 0.8 }
```

For a request, `status` is `nil` and `error` names the error class when no response arrived, and `duration` is milliseconds on the wire. A retry names the attempt about to be sent and what the last one got. `wait` is in seconds. The token is never in any of them.

## Retries and the rate limit

Pennylane allows 25 requests per 5 seconds per token. The client keeps one bucket per token for the whole process, shared by every client and thread, and corrects it from the `ratelimit-remaining` and `ratelimit-reset` headers on every response. When the bucket is empty, a call waits for the window to reset.

Retries follow one rule: never send a write twice unless Pennylane said it did not run it.

| Answer | GET | POST, PUT, DELETE |
|---|---|---|
| 429 | retried after `retry-after` | retried after `retry-after` |
| 500, 502, 503, 504 | retried | raised |
| `ConnectionError`, `TimeoutError` | retried | raised |
| anything else | raised | raised |

A call makes at most 3 attempts, with a random backoff (up to 0.5 s, then 1 s), and waits at most 30 s in total. A `retry-after` that would pass the 30 s raises `RateLimitError` at once, with `#retry_after` set. Change the cap per client:

```ruby
PennylaneClient.new(token:, max_retry_wait: 10)
```

When you know a write is safe to repeat, opt in per call. `retry` is not sent to Pennylane:

```ruby
client.call(:putCategoryGroup, id: 7, label: "Sales", retry: :always)
```

### Share the budget across processes

The bucket is per process. Several processes on one token each think they have 25 requests; the headers and 429 retries absorb the overlap. To share one budget, give the client a registry that builds your own limiter. A limiter responds to `acquire` (wait for a call, return the seconds waited) and `update(remaining:, reset_at:)` (`reset_at` is a Unix time or `nil`). The key is a SHA-256 of the token:

```ruby
limiters = PennylaneClient::LimiterRegistry.new { |key| MyRedisLimiter.new("pennylane:#{key}") }
client = PennylaneClient.new(token:, limiters:)
```

## Walk a list

`client.paginate` returns every item of a list operation, lazily. It follows `next_cursor` and sends your `filter` and `sort` again on every page, because Pennylane's cursor does not remember them. Pass `filter` as an Array of Hashes; the client sends the JSON string Pennylane expects.

```ruby
drafts = [{ field: "status", operator: "eq", value: "draft" }]

client.paginate(:getCustomerInvoices, filter: drafts, sort: "-id").each do |invoice|
  puts invoice[:invoice_number]
end

client.paginate(:getCustomerInvoices).first(10)   # one request
```

A named list method does the same: `client.customer_invoices.list(filter: drafts, sort: "-id")`.

Each page asks for the largest `limit` the operation allows (100, or 1000 for the changelogs, ledger accounts and trial balance). Pass a smaller `limit:` to get smaller pages. To see each page, with `has_more` and `next_cursor`, use `client.pages` instead.

## Upload a file

Pass a `File`, an IO or a `Pathname` as the file field. The file streams from disk, so a 100 MB upload does not load 100 MB into memory. The filename comes from the path and the content type from the extension (`.pdf`, `.png`, `.jpg`, `.tiff`, `.bmp`, `.gif`, `.xml`).

```ruby
client.call(:postFileAttachments, file: Pathname("receipt.pdf"))

File.open("invoice.pdf", "rb") do |file|
  client.call(:postCustomerInvoiceAppendices, customer_invoice_id: 42, file:)
end
```

Wrap it in `PennylaneClient::Upload` to set the filename or the content type yourself. Hash and Array fields go as JSON parts:

```ruby
xml = PennylaneClient::Upload.new(io, filename: "invoice.xml", content_type: "application/xml")
client.call(:createCustomerInvoiceEInvoiceImport, file: xml, invoice_options: { customer_id: 12 })
```

An upload gets 300 s to read and write. Change it with `PennylaneClient::NetHttpTransport.new(upload_timeout: 600)`, passed as `transport:`. A file you open stays open; the client closes only what it opened from a `Pathname`. An IO must respond to `size`, so a pipe cannot be uploaded.

## Work with customer invoices

`client.customer_invoices` names every Customer Invoices operation. Most names say what they do (`find`, `update`, `finalize`, `mark_as_paid`). These are the ones you would not guess.

Every list walks all its pages lazily, including the ones under one invoice:

```ruby
invoices = client.customer_invoices

invoices.invoice_lines(42).each { |line| ... }
invoices.payments(42, sort: "-id").first(5)
# also: invoice_line_sections, matched_transactions, custom_header_fields, appendices, categories
```

`appendices` and `categories` take no `sort:`; the others do.

`send_by_email` and `send_to_pa` raise `ConflictError` while Pennylane is still generating the PDF or processing an e-invoice import. The client never retries a 409, so try again later:

```ruby
invoices.send_by_email(42)                                     # to the customer's addresses
invoices.send_by_email(42, recipients: ["billing@example.com"])
invoices.send_to_pa(42)                                        # to the Partner Dematerialization Platform
```

`categorize` replaces an invoice's categories. The body is a bare array, so it is the second argument. Within one category group the weights must add up to 1:

```ruby
invoices.categorize(42, [{ id: 426, weight: "0.6575" }, { id: 427, weight: "0.3425" }])
```

Three ways to bring in an invoice issued elsewhere:

```ruby
invoices.create_from_quote(quote_id: 9, draft: true)
invoices.import(file_attachment_id: 5, customer_id: 7, ...)     # PDF uploaded first with postFileAttachments
invoices.import_e_invoice(Pathname("facturx.pdf"), invoice_options: { customer_id: 7 })
```

`import` stores the amounts exactly as sent, so they must add up. `import_e_invoice` takes a Factur-X PDF, or a UBL or CII XML invoice (alpha at Pennylane), and streams it like any [upload](#upload-a-file). `upload_appendix(42, file)` attaches a PDF or image to an invoice the same way.

`link_credit_note(42, credit_note_id: 43)` links credit note 43 to invoice 42. `mark_installment_as_paid(42, 3)` marks one installment paid; Pennylane tags it Hidden and alpha, so it may change.

## Handle a validation error

```ruby
begin
  client.call(:postJournals, code: "HA")
rescue PennylaneClient::ValidationError => e
  e.message   # "422 unprocessable_entity: ..."
  e.details   # { field: "label", issue: "is required" }, when Pennylane sends it
end
```
