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

Send amounts as strings too. Pennylane rejects numeric amounts with a 400.
