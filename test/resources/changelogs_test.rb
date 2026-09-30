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
