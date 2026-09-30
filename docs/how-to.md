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

Each request writes one line and fires one event, a frozen Hash:

```ruby
{ operation_id: :getMe, method: "GET", path: "/api/external/v2/me", status: 200, error: nil, duration: 84.2 }
```

`status` is `nil` and `error` names the error class when no response arrived. The token is never in either.

## Handle a validation error

```ruby
begin
  client.call(:postJournals, code: "HA")
rescue PennylaneClient::ValidationError => e
  e.message   # "422 unprocessable_entity: ..."
  e.details   # { field: "label", issue: "is required" }, when Pennylane sends it
end
```
