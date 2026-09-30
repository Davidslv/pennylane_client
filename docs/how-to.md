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

The registry drops a limiter no one has fetched for 60 s (`idle_after:` changes it) and builds a new one the next time the token is used. If your limiter answers `idle?`, it is dropped only when that returns true.

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
client.file_attachments.upload(Pathname("receipt.pdf"))   # => { id: 5, ... }

File.open("invoice.pdf", "rb") do |file|
  client.call(:postCustomerInvoiceAppendices, customer_invoice_id: 42, file:)
end
```

Wrap it in `PennylaneClient::Upload` to set the filename or the content type yourself. Hash and Array fields go as JSON parts:

```ruby
xml = PennylaneClient::Upload.new(io, filename: "invoice.xml", content_type: "application/xml")
client.call(:createCustomerInvoiceEInvoiceImport, file: xml, invoice_options: { customer_id: 12 })
```

An upload gets 300 s to read and write. Change it with `PennylaneClient::NetHttpTransport.new(upload_timeout: 600)`, passed as `transport:`. A file you open stays open; the client closes only what it opened from a `Pathname`. A `Pathname` is checked before anything is sent: a missing file raises `Errno::ENOENT`, and a directory or a file you cannot read raises `ArgumentError`. An IO must respond to `size`, so a pipe cannot be uploaded.

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
invoices.import(file_attachment_id: 5, customer_id: 7, ...)     # PDF uploaded first with file_attachments.upload
invoices.import_e_invoice(Pathname("facturx.pdf"), invoice_options: { customer_id: 7 })
```

`import` stores the amounts exactly as sent, so they must add up. `import_e_invoice` takes a Factur-X PDF, or a UBL or CII XML invoice (alpha at Pennylane), and streams it like any [upload](#upload-a-file). `upload_appendix(42, file)` attaches a PDF or image to an invoice the same way.

`link_credit_note(42, credit_note_id: 43)` links credit note 43 to invoice 42. `mark_installment_as_paid(42, 3)` marks one installment paid; Pennylane tags it Hidden and alpha, so it may change.

## Work with customers

`client.customers` names every Customers operation. Pennylane keeps company and individual customers apart. `list` and `find` return both, and each item's `customer_type` says which. Create and update through the kind:

```ruby
customers = client.customers
address = { address: "8 rue de la paix", postal_code: "75002", city: "Paris", country_alpha2: "FR" }

acme = customers.create_company(name: "Acme", billing_address: address)
ada  = customers.create_individual(first_name: "Ada", last_name: "Lovelace", billing_address: address)

customers.update_company(acme[:id], payment_conditions: "30_days")
customers.update_individual(ada[:id], emails: ["ada@example.org"])
customers.find_company(acme[:id])     # also find_individual; find(id) works for either
```

`create` is `postCustomer`, which makes either kind from `customer_type:`. Pennylane tags it Hidden, so it may change. Prefer `create_company` and `create_individual`:

```ruby
customers.create(customer_type: "company", name: "Acme", billing_address: address)
```

Contacts belong to one customer, so every contact method takes the customer id first. A contact is its own record. Adding, changing or deleting one does not touch the customer's invoice recipients (`emails`):

```ruby
customers.contacts(7, sort: "-id").each { |contact| ... }
contact = customers.create_contact(7, first_name: "Grace", last_name: "Hopper", email: "grace@example.org")
customers.update_contact(7, contact[:id], role: "CFO")
customers.delete_contact(7, contact[:id])
```

`categories(7)` lists a customer's categories. `categorize` replaces them with a bare array, like the invoice one:

```ruby
customers.categorize(7, [{ id: 426, weight: "0.6575" }, { id: 427, weight: "0.3425" }])
```

## Work with supplier invoices and suppliers

`client.supplier_invoices` and `client.suppliers` name every Supplier Invoices and Suppliers operation. A supplier invoice has no `create`. It comes in by import, from a PDF uploaded first with `client.file_attachments.upload`, or from an e-invoice file:

```ruby
invoices = client.supplier_invoices

invoices.import(file_attachment_id: 5, supplier_id: 12, date: Date.today, deadline: Date.today + 30,
                currency_amount_before_tax: "100", currency_amount: "120", currency_tax: "20",
                invoice_lines: [{ currency_amount: "120", currency_tax: "20", vat_rate: "FR_200" }])
invoices.import_e_invoice(Pathname("facturx.pdf"), invoice_options: { supplier_id: 12 })
```

Pennylane de-duplicates supplier invoice files: importing the same file twice raises `ConflictError`. `import` also raises `ConflictError` while the uploaded file is not ready yet; Pennylane says to try again after a few seconds. The client never retries a 409. A `ConflictError` that persists most likely means the file was imported before.

`import_e_invoice` takes a Factur-X PDF, or a UBL or CII XML invoice (alpha at Pennylane), and streams it like any [upload](#upload-a-file).

`ValidateAccountingSupplierInvoice` is `validate_accounting(42)`. Payment status and e-invoice status take their value as a keyword. `update_payment_status` returns true:

```ruby
invoices.update_payment_status(42, payment_status: "paid")        # or "to_be_paid"
invoices.update_e_invoice_status(42, status: "disputed", reason: "incorrect_vat_rate")
invoices.update_e_invoice_status(42, status: "refused", reason: "duplicate_invoice")   # archives it for good
invoices.update_e_invoice_status(42, status: "approved")          # lifts a dispute
```

`update_e_invoice_status` is for invoices received through the PA. A transition the invoice cannot make, such as disputing one with payments, raises `ValidationError`.

`update` takes `invoice_lines:` as `{ create: [...], update: [...], delete: [...] }`, not a plain array. `link_purchase_request(42, purchase_request_id: 8)` links one purchase request; call it once for each.

The lists under one invoice walk every page lazily: `invoice_lines`, `payments`, `matched_transactions` (all take `sort:`) and `categories` (no `sort:`). `categorize` replaces an invoice's or a supplier's categories with a bare array:

```ruby
invoices.categorize(42, [{ id: 426, weight: "0.6575" }, { id: 427, weight: "0.3425" }])
client.suppliers.categorize(12, [{ id: 426, weight: "1" }])
```

Suppliers have `list`, `find`, `create`, `update`, `categories` and `categorize`. `create` needs `name:` and raises `ConflictError` when the supplier already exists.

## Work with mandates

The Mandates operations split into three resources, one per kind of mandate:

```ruby
client.sepa_mandates          # list, find, create, update, delete
client.gocardless_mandates    # list, find, send_request, associate, cancel
client.pro_account_mandates   # list, send_request, migration_candidates, migrate
```

A SEPA mandate is one you record yourself. `create` needs `customer_id:`, `iban:`, `bic:`, `identifier:` and `signed_at:`:

```ruby
client.sepa_mandates.create(customer_id: 7, iban: "FR7630006000011234567890189", bic: "AGRIFRPP",
                            identifier: "MANDATE-1", signed_at: Date.new(2026, 9, 1), sequence_type: "RCUR")
```

For GoCardless, `send_request` emails a customer a link to set up a mandate; `email:` needs `recipients:`. `associate` links an existing mandate to a customer. `cancel` works only on a `pending_submission`, `submitted` or `active` mandate; Pennylane rejects any other with a 400 or 422, both `ValidationError`. All three return true:

```ruby
mandates = client.gocardless_mandates
mandates.send_request(customer_id: 7, email: { recipients: ["billing@acme.example"], subject: "Direct debit" })
mandates.associate(5, customer_id: 7)
mandates.cancel(5)
```

Pro Account mandates need a Pennylane Pro Account and an enabled merchant profile. Without the Pro Account every call raises `NotFoundError`; without the merchant profile, `PermissionError`. `getCompanyFeatures` (`client.call(:getCompanyFeatures)`) is where Pennylane lists company features, but today it reports only `installments`, not the Pro Account or the merchant profile, so the 404 or 403 is the check. `migrate` moves a SEPA or GoCardless mandate to the Pro Account; only a candidate with status `available` can migrate. Its answer wraps the migration in `mandate_migration:`. `send_request` returns true:

```ruby
pro = client.pro_account_mandates
pro.migration_candidates(filter: [{ field: "status", operator: "eq", value: "available" }]).first
pro.migrate(mandate_type: "SepaMandate", mandate_id: 3)[:mandate_migration]   # "Mandate" for a GoCardless one
pro.send_request(customer_id: 7)
```

## Work with transactions and bank accounts

`client.transactions`, `client.bank_accounts` and `client.bank_establishments` name every Transactions and bank operation. A transaction lives in a bank account; `create` needs `bank_account_id:`, `label:`, `date:` and `amount:`:

```ruby
account = client.bank_accounts.create(name: "Main account", iban: "FR7630006000011234567890189")
tx = client.transactions.create(bank_account_id: account[:id], label: "Card payment", date: Date.today, amount: "-12.50")
```

Bank accounts have `list`, `find` and `create`, and no update or delete. `account_type: "current"` is deprecated; use `"checking"`. A bank account's optional `bank_establishment_id:` is an id from `client.bank_establishments.list`.

`update` sets the transaction's third party and nothing else. Pass `customer_id:` or `supplier_id:`, not both. Both are nullable in the contract, so `nil` sends `null` (not yet checked against the sandbox):

```ruby
client.transactions.update(tx[:id], supplier_id: 12)
```

Match a transaction from the invoice's side. Call `match_transaction` once per transaction; one transaction can match several invoices. Customer invoices must not be drafts. Both calls return true:

```ruby
client.customer_invoices.match_transaction(42, transaction_id: tx[:id])
client.customer_invoices.unmatch_transaction(42, tx[:id])
client.supplier_invoices.match_transaction(51, transaction_id: tx[:id])   # also unmatch_transaction
```

`matched_invoices(tx[:id])` lists what a transaction is matched to; the invoice resources' `matched_transactions` go the other way. `categories` and `matched_invoices` take no `sort:`. `categorize` replaces the categories with a bare array; categories from different groups can be mixed, and each group's weights add up to 1:

```ruby
client.transactions.categorize(tx[:id], [{ id: 59, weight: "0.5" }, { id: 33, weight: "0.5" }, { id: 65, weight: "1" }])
```

## Work with quotes and commercial documents

`client.quotes` and `client.commercial_documents` name every Quotes and Commercial Documents operation. A commercial document is a proforma, a shipping order or a purchasing order; `document_type:` says which, and it cannot change later:

```ruby
lines = [{ label: "Audit", quantity: 2, raw_currency_unit_price: "450", unit: "day", vat_rate: "FR_200" }]

quote = client.quotes.create(customer_id: 7, date: Date.today, deadline: Date.today + 30, invoice_lines: lines)
client.commercial_documents.create(document_type: "proforma", customer_id: 7, date: Date.today,
                                   deadline: Date.today + 30, invoice_lines: lines)
```

Pennylane numbers each document from the company's numbering for its type. Without one, it refuses to create that commercial document, number a quote or finalize a customer invoice. Numberings are configured in the Pennylane app; `client.numberings.list` shows which exist: `estimate` for quotes, `proforma`, `shipping_order` and `purchasing_order` for commercial documents, `invoice` for customer invoices:

```ruby
client.numberings.list.map { _1[:document_type] }   # => ["invoice", "estimate", ...]
```

`update` takes `invoice_lines:` as `{ create: [...], update: [...], delete: [...] }`, not a plain array. A commercial document's `invoice_line_sections:` works the same way.

A quote has a status. `update_status` sets it to `"pending"`, `"accepted"`, `"denied"`, `"invoiced"` or `"expired"`. `send_by_email` works like the invoice one: it returns true, and raises `ConflictError` while Pennylane is still generating the PDF:

```ruby
client.quotes.update_status(quote[:id], status: "accepted")
client.quotes.send_by_email(quote[:id], recipients: ["billing@example.com"])
client.customer_invoices.create_from_quote(quote_id: quote[:id], draft: true)
```

Both resources list what hangs off one document: `invoice_lines` and `invoice_line_sections` (both take `sort:`) and `appendices` (no `sort:`). `upload_appendix(id, file)` attaches a PDF or image, streamed like any [upload](#upload-a-file).

`client.customer_invoice_templates.list` lists the customer invoice templates. The API has no call to create or change one.

## Work with the ledger

`client.journals`, `client.ledger_accounts`, `client.ledger_entries`, `client.ledger_entry_lines`, `client.fiscal_years`, `client.trial_balance` and `client.file_attachments` name every ledger operation.

A ledger entry needs a journal and balanced lines. Amounts are Strings or BigDecimals. `create` takes the lines as a plain array; `update` takes them as `{ create: [...], update: [...], delete: [...] }`:

```ruby
bank = client.ledger_accounts.list(filter: [{ field: "number", operator: "eq", value: "512" }]).first
entry = client.ledger_entries.create(date: Date.today, label: "Rent", journal_id: 4,
                                     ledger_entry_lines: [{ debit: "1200", credit: "0", ledger_account_id: 21 },
                                                          { debit: "0", credit: "1200", ledger_account_id: bank[:id] }])
client.ledger_entries.update(entry[:id], ledger_entry_lines: { update: [{ id: 91, label: "Rent, March" }] })
```

Pennylane may return the lines in a different order from the one you sent. Match them by debit, credit or label, not by position.

A ledger account number starting with 401 also creates a supplier, and one starting with 411 a company customer.

Lines are listed, lettered and categorized on `client.ledger_entry_lines`. `letter` and `unletter` both require `unbalanced_lettering_strategy:`: `"none"` makes Pennylane refuse an unbalanced lettering with a `ValidationError`, `"partial"` allows it. Lettering a line that is already lettered brings its whole lettering along. `unletter` is a DELETE with a body and returns true:

```ruby
lines = client.ledger_entry_lines
lines.letter([{ id: 91 }, { id: 95 }], unbalanced_lettering_strategy: "none")   # => every line of the lettering
lines.lettered_lines(91).to_a
lines.unletter([{ id: 95 }], unbalanced_lettering_strategy: "none")               # => true
lines.categorize(91, [{ id: 59, weight: "0.5" }, { id: 33, weight: "0.5" }])     # [] removes them all
```

The trial balance needs a period. It comes back one Hash per account, 1000 to a page:

```ruby
client.trial_balance.list(period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 12, 31))
                    .each { puts [_1[:number], _1[:debits], _1[:credits]].join("\t") }
```

To attach a receipt to an entry, upload it with `client.file_attachments.upload` and pass the id as `file_attachment_id:`. The contract says that field will soon be deprecated. The deprecated `postLedgerAttachments` has no named method.

## Work with categories and products

`client.categories`, `client.category_groups` and `client.products` name every Categories, Category Groups and Products operation.

An analytical category lives in a category group. Create the group first; its `kind:` is `"profit_and_loss"`, `"treasury"` or `"building"`. A treasury category also takes `direction:`, which defaults to `"cash_out"`:

```ruby
group = client.category_groups.create(label: "Teams", kind: "profit_and_loss")
marketing = client.categories.create(label: "Marketing", category_group_id: group[:id], analytical_code: "MKT")
client.category_groups.categories(group[:id]).map { _1[:label] }   # => ["Marketing"]
```

`category_groups.update` requires `label:` even when you change only `kind:`. `categories.update` takes `label:`, `analytical_code:` and `direction:`; it does not move a category to another group.

These resources manage the categories themselves. To put a category on an invoice, transaction, customer, supplier or ledger entry line, use `categorize` on that resource. It takes the bare array of `{ id:, weight: }`.

A product needs `label:`, `price_before_tax:` and `vat_rate:`. Invoice and quote lines can point at it with `product_id:`:

```ruby
day = client.products.create(label: "Consulting day", price_before_tax: BigDecimal("650"), vat_rate: "FR_200",
                             unit: "day", reference: "CONS-DAY")
client.products.list(filter: [{ field: "reference", operator: "eq", value: "CONS-DAY" }]).first
```

## Read the changelogs

`client.changelogs` names the ten change feeds: `customer_invoices`, `customers`, `ledger_entries_categories`, `ledger_entry_lines`, `ledger_entry_lines_categories`, `products`, `quotes`, `supplier_invoices`, `suppliers` and `transactions`. Each returns the changes lazily, oldest `processed_at` first. A change carries the record's `id` and its `operation` (`"insert"`, `"update"` or `"delete"`), not the record itself:

```ruby
client.changelogs.customer_invoices(since: Time.now - 3600).each do |change|
  next if change[:operation] == "delete"

  sync(client.customer_invoices.find(change[:id]))
end
```

Pennylane keeps four weeks of changes. A `since:` older than that raises `ValidationError` (422). Without `since:` the feed starts at the oldest change kept. `since:` is sent with the first page only, because Pennylane answers 400 to `start_date` next to a `cursor`.

To resume where the last run stopped, keep the `processed_at` of the last change you handled and pass it as `since:` next time. The last page's `next_cursor` is null, so it cannot carry you forward. `processed_at` carries microseconds. Pass it back as the String, or as a Time parsed from it: a Time is sent with its microseconds (`2025-06-25T11:54:18.589480Z`), so the feed does not restart earlier in that second. The contract does not say whether `start_date` includes a change at that exact time, so handle a repeat of the last change:

```ruby
last_seen = nil
client.changelogs.customer_invoices(since: saved_processed_at).each do |change|
  sync(change[:id])
  last_seen = change[:processed_at]
end
save(last_seen) if last_seen
```

## Run an export

`client.exports` names the FEC, General Ledger and Analytical General Ledger exports. Pennylane builds an export in the background; `generate_*` asks for one and reads it until it is ready:

```ruby
export = client.exports.generate_fec(period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 6, 30))
export[:file_url]   # expires 30 minutes after it is issued
```

It reads the export every 5 s for up to 300 s. Change both with `interval:` and `timeout:`. It raises `ExportError` when the export ends in `error` or is still pending at the timeout; `error.export[:id]` lets you check on it later with `find_fec`. A read that fails on its own (a 5xx after its retries, no response) raises the usual error instead, without the export id; call `create_fec` and `find_fec` yourself if you need to keep the id through that. `generate_analytical_general_ledger` also takes `mode:` (`"in_line"`, the default, or `"in_column"`).

To poll on your own schedule, call the two halves yourself: `create_fec(period_start:, period_end:)` returns the pending export and `find_fec(id)` reads it. The same pairs exist for `general_ledger` and `analytical_general_ledger`.

## Check the token and the company

`client.users.me` returns the token's `:user`, `:company` and `:scopes`. `:user` can be nil; the contract does not say when. `:scopes` lists what the token may do.

Some features depend on the company's plan or on a rollout. `client.company.features` says which are on. Check it before you send a gated field, because Pennylane does not always refuse one it cannot honour:

```ruby
if client.company.features[:installments]
  client.customer_invoices.create(**invoice, installments:)
else
  client.customer_invoices.create(**invoice)
end
```

With `installments` off, an invoice sent with installments either gets a 403 or is created with a single installment. Pennylane adds keys here as it gates new features.

`client.pa_registrations.list` returns the company's registrations with a Plateforme Agréée. The company has finished PA onboarding when a registration is `"activated"` with the `exchange_direction` you need. A nil `siret` is the head office (SIREN). The list is one request: Pennylane takes no cursor for it. If Pennylane answers `has_more: true`, `list` raises `PennylaneClient::Error` rather than return part of the list.

## Work with billing subscriptions

`client.billing_subscriptions` names every Billing Subscriptions operation. Pennylane issues a customer invoice on each occurrence of the recurring rule.

The request shape differs from what you read back. Send `mode:` as a Hash and `recurring_rule:` with `type:`; read back `mode` as a String and `recurring_rule[:rule_type]`. Send `customer_id:`; read back `customer: { id:, url: }`.

```ruby
line = { label: "Hosting", quantity: 1, unit: "month", raw_currency_unit_price: BigDecimal("49.90"), vat_rate: "FR_200" }
subscription = client.billing_subscriptions.create(
  start: Date.new(2026, 10, 1), customer_id: 3, payment_conditions: "30_days", payment_method: "offline",
  mode: { type: "email", email_settings: { recipients: ["billing@example.com"] } },
  recurring_rule: { type: "monthly", interval: 1, day_of_month: 1 },
  customer_invoice_data: { invoice_lines: [line] }
)
```

`mode:` is `{ type: "awaiting_validation" }`, `{ type: "finalized" }` or the email form above. The email form needs an email template set up in Pennylane.

To stop a subscription in progress, `update(id, stop: true)`; `stop: false` resumes it. `update` changes invoice lines and sections through lists, not by replacing them:

```ruby
client.billing_subscriptions.update(subscription[:id], customer_invoice_data: {
  invoice_lines: { create: [line], update: [{ id: 11, quantity: 2 }], delete: [{ id: 12 }] }
})
```

`invoice_lines(id)` and `invoice_line_sections(id)` walk the current lines and sections.

## Import a purchase order

`client.purchase_requests` lists and reads purchase requests, and `import` creates one from a purchase order. The body is JSON: upload the order first and pass the attachment id. Pennylane approves an imported request straight away.

```ruby
attachment = client.file_attachments.upload(Pathname("po-1042.pdf"))
client.purchase_requests.import(
  file_attachment_id: attachment[:id], supplier_id: 4, reason: "Laptops", purchase_order_number: "PO-1042",
  currency_amount_before_tax: BigDecimal("1000"), currency_tax: BigDecimal("200"), currency_amount: BigDecimal("1200"),
  delivery_address: { address: "1 rue de Rivoli", postal_code: "75001", city: "Paris", country_alpha2: "FR" },
  purchase_request_lines: [{ label: "Laptop", quantity: 2, unit: "piece", unit_price: BigDecimal("500"),
                             vat_rate: "FR_200", currency_amount: BigDecimal("1200"), currency_tax: BigDecimal("200") }]
)
```

## Subscribe to webhooks

`client.webhook_subscriptions` names the Webhooks operations. Webhooks are in beta at Pennylane, which suggests the changelogs as a fallback.

```ruby
hook = client.webhook_subscriptions.create(callback_url: "https://example.com/pennylane",
                                           events: ["customer_invoice.e_invoicing_status_updated"])
store_secret(hook[:secret])
```

The create response is the only place the secret appears. `find` and `list` leave it out, and `update` takes no secret. The contract has no way to rotate it; creating a new subscription and deleting the old one gets you a new secret. The events are `customer_invoice.e_invoicing_status_updated`, `dms_file.created` and `supplier_invoice.e_invoicing_received`. A company-scoped token allows 10 subscriptions per company; an app-bound token allows 10 in all.

Pennylane can disable a subscription whose endpoint keeps failing. `find(id)` shows `enabled`, `disabled_reason` and `consecutive_failures`. `update(id, enabled: true)` sends the flag to turn it back on; the contract does not say whether that works after a `permanent_error`.

## Verify an inbound webhook

Pennylane signs each delivery with `X-Pennylane-Signature: t=<unix seconds>,v1=<hex>`. `Webhook.verify!` recomputes the HMAC-SHA256 of `"{t}.{raw_body}"` with the subscription secret, compares it in constant time, rejects a `t` more than `tolerance` seconds (default 300) from now, and returns the event as a deep-frozen Hash with symbol keys.

```ruby
# Rails
def create
  event = PennylaneClient::Webhook.verify!(request.raw_post, request.headers["X-Pennylane-Signature"],
                                           secret: ENV.fetch("PENNYLANE_WEBHOOK_SECRET"))
  ProcessPennylaneEvent.perform_later(event[:id], event[:event], event[:data]) unless seen?(event[:id])
  head :ok
rescue PennylaneClient::SignatureError
  head :bad_request
end
```

- Pass the raw body bytes as received. Parsing and re-serialising the JSON changes the bytes and the signature will not match.
- Delivery is at-least-once and unordered. De-duplicate on the delivery `event[:id]`, and reconcile state from the payload, not from arrival order. Storing seen ids is up to you.
- Answer 2xx within a few seconds and do the work in a background job; a slow answer counts as a failed delivery and is retried.
- `tolerance: nil` skips the timestamp check. A header that is missing, malformed or in a broken encoding raises `SignatureError`, never anything else. `SignatureError` never carries the secret or the expected digest. A blank secret raises `ArgumentError`.

## Handle a validation error

```ruby
begin
  client.call(:postJournals, code: "HA")
rescue PennylaneClient::ValidationError => e
  e.message   # "422 unprocessable_entity: ..."
  e.details   # { field: "label", issue: "is required" }, when Pennylane sends it
end
```
