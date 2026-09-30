# frozen_string_literal: true

require "test_helper"

# Changelogs: `client.changelogs`. Each stub is the method and path from the
# operation's reference page. Pennylane keeps four weeks of changes and
# answers 400 to `start_date` next to a `cursor`.
class ChangelogsTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"
  SINCE = Time.utc(2026, 9, 29, 10, 0, 0)

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def changelogs = client.changelogs

  def page(*ids, next_cursor: nil)
    JSON.generate({ items: ids.map { { id: _1, operation: "update" } }, has_more: !next_cursor.nil?, next_cursor: })
  end

  # Stubs a one-page feed at `path`, read from SINCE.
  def stub_since(path)
    stub_request(:get, "#{API}/changelogs/#{path}")
      .with(query: { start_date: "2026-09-29T10:00:00Z", limit: "1000" }).to_return(status: 200, body: page(7))
  end

  def ids(changes) = changes.map { _1[:id] }.to_a

  def test_is_one_resource_per_client
    assert_same client.changelogs, client.changelogs
    refute_includes client.changelogs.inspect, "tok"
  end

  # names: getCustomerInvoicesChanges
  def test_customer_invoices_walks_on_by_cursor_without_start_date
    since = { start_date: "2026-09-29T10:00:00Z", limit: "1000" }
    stub_request(:get, "#{API}/changelogs/customer_invoices").with(query: since)
                                                             .to_return(status: 200, body: page(1, next_cursor: "c2"))
    stub_request(:get, "#{API}/changelogs/customer_invoices").with(query: { cursor: "c2", limit: "1000" })
                                                             .to_return(status: 200, body: page(2))

    assert_equal [1, 2], ids(changelogs.customer_invoices(since: SINCE))
  end

  # Resuming from a parsed processed_at must not start up to a second early.
  def test_since_keeps_the_microseconds_of_a_processed_at
    since = { start_date: "2025-06-25T11:54:18.589480Z", limit: "1000" }
    stub_request(:get, "#{API}/changelogs/transactions").with(query: since).to_return(status: 200, body: page(3))

    assert_equal [3], ids(changelogs.transactions(since: Time.parse("2025-06-25T11:54:18.589480Z")))
  end

  def test_without_since_starts_from_the_oldest_change
    stub_request(:get, "#{API}/changelogs/customer_invoices").with(query: { limit: "1000" })
                                                             .to_return(status: 200, body: page(1))

    assert_equal [1], ids(changelogs.customer_invoices)
  end

  def test_passes_other_params_through
    stub_request(:get, "#{API}/changelogs/customers").with(query: { limit: "50" })
                                                     .to_return(status: 200, body: page(3))

    assert_equal [3], ids(changelogs.customers(limit: 50))
  end

  FEEDS = %i[customer_invoices customers ledger_entries_categories ledger_entry_lines
             ledger_entry_lines_categories products quotes supplier_invoices suppliers transactions].freeze

  # `since:` is the one spelling. Pennylane's own `start_date:` next to it
  # used to win silently; alone it was a second way to say the same thing.
  def test_every_feed_refuses_start_date_and_points_to_since
    assert_equal FEEDS.sort, PennylaneClient::Resources::Changelogs.public_instance_methods(false).sort

    FEEDS.each do |feed|
      [{ start_date: "2026-09-20T00:00:00Z" }, { since: SINCE, start_date: "2026-09-20T00:00:00Z" }].each do |args|
        error = assert_raises(ArgumentError, "#{feed}(#{args})") { changelogs.public_send(feed, **args) }
        assert_includes error.message, "since:"
      end
    end
  end

  # A String key would slip past a Symbol-only guard: "start_date" next to
  # since: sent two start_date params, and "since" went as a param Pennylane
  # does not take.
  def test_every_feed_refuses_string_keys_for_since_and_start_date
    stub = stub_request(:get, %r{/changelogs/}).to_return(status: 200, body: page(7))
    FEEDS.each do |feed|
      [{ "start_date" => SINCE }, { since: SINCE, "start_date" => SINCE }, { "since" => SINCE }].each do |args|
        error = assert_raises(ArgumentError, "#{feed}(#{args})") { changelogs.public_send(feed, **args).first }
        assert_includes error.message, "since:"
      end
    end
    assert_not_requested stub
  end

  # names: getCustomerChanges
  def test_customers
    stub_since("customers")

    assert_equal [7], ids(changelogs.customers(since: SINCE))
  end

  # names: getLedgerEntriesCategoryChanges
  def test_ledger_entries_categories
    stub_since("ledger_entries_categories")

    assert_equal [7], ids(changelogs.ledger_entries_categories(since: SINCE))
  end

  # names: getLedgerEntryLineChanges
  def test_ledger_entry_lines
    stub_since("ledger_entry_lines")

    assert_equal [7], ids(changelogs.ledger_entry_lines(since: SINCE))
  end

  # names: getLedgerEntryLinesCategoryChanges
  def test_ledger_entry_lines_categories
    stub_since("ledger_entry_lines_categories")

    assert_equal [7], ids(changelogs.ledger_entry_lines_categories(since: SINCE))
  end

  # names: getProductChanges
  def test_products
    stub_since("products")

    assert_equal [7], ids(changelogs.products(since: SINCE))
  end

  # names: getQuoteChanges
  def test_quotes
    stub_since("quotes")

    assert_equal [7], ids(changelogs.quotes(since: SINCE))
  end

  # names: getSupplierInvoicesChanges
  def test_supplier_invoices
    stub_since("supplier_invoices")

    assert_equal [7], ids(changelogs.supplier_invoices(since: SINCE))
  end

  # names: getSupplierChanges
  def test_suppliers
    stub_since("suppliers")

    assert_equal [7], ids(changelogs.suppliers(since: SINCE))
  end

  # names: getTransactionChanges
  def test_transactions
    stub_since("transactions")

    assert_equal [7], ids(changelogs.transactions(since: SINCE))
  end
end

# What `since:` takes. Pennylane's start_date is a date-time (RFC 3339).
class ChangelogsSinceTest < Minitest::Test
  API = ChangelogsTest::API

  def changelogs = PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new).changelogs
  def page(id) = JSON.generate({ items: [{ id:, operation: "update" }], has_more: false, next_cursor: nil })
  def ids(changes) = changes.map { _1[:id] }.to_a

  def test_takes_a_date_time_string
    since = { start_date: "2026-09-29T10:00:00Z", limit: "1000" }
    stub_request(:get, "#{API}/changelogs/customers").with(query: since).to_return(status: 200, body: page(4))

    assert_equal [4], ids(changelogs.customers(since: "2026-09-29T10:00:00Z"))
  end

  def test_takes_a_date_time
    since = { start_date: "2026-09-29T10:00:00+00:00", limit: "1000" }
    stub_request(:get, "#{API}/changelogs/suppliers").with(query: since).to_return(status: 200, body: page(5))

    assert_equal [5], ids(changelogs.suppliers(since: DateTime.new(2026, 9, 29, 10, 0, 0)))
  end

  # A Date was sent as "2026-09-29", which the contract does not say
  # Pennylane accepts, and anything else went as its to_s.
  def test_every_feed_refuses_a_since_that_is_not_a_time_or_a_string
    stub = stub_request(:get, %r{/changelogs/}).to_return(status: 200, body: page(7))
    ChangelogsTest::FEEDS.each do |feed|
      [Date.new(2026, 9, 29), 1_782_864_000].each do |since|
        error = assert_raises(ArgumentError, "#{feed}(since: #{since.inspect})") do
          changelogs.public_send(feed, since:).first
        end
        assert_includes error.message, "Time or an RFC 3339 String"
      end
    end
    assert_not_requested stub
  end
end
