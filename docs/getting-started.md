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

Planned:

```ruby
require "pennylane_client"

client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))
client.call(:getMe)
```

## What comes back

Responses are deep-frozen Hashes with symbol keys, exactly as Pennylane sends them. Money is a decimal string and dates are ISO 8601 strings:

```ruby
BigDecimal(invoice[:amount])   # "230.32" -> 0.23032e3
Date.iso8601(invoice[:date])
```
