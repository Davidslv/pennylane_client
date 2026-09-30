# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "date"

# Ledger accounts and ledger entries: `client.ledger_accounts`,
# `client.ledger_entries`. Each stub is the method and path from the
# operation's reference page.
class LedgerAccountsAndEntriesTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"
  # A balanced pair of lines as the Encoder sends BigDecimal amounts.
  SENT_LINES = [{ debit: "1200.5", credit: "0.0", ledger_account_id: 613 },
                { debit: "0.0", credit: "1200.5", ledger_account_id: 512 }].freeze

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def accounts = client.ledger_accounts
  def entries = client.ledger_entries

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    %i[ledger_accounts ledger_entries].each do |name|
      assert_same client.public_send(name), client.public_send(name)
      refute_includes client.public_send(name).inspect, "tok"
    end
  end

  # names: getLedgerAccounts
  def test_accounts_list_asks_for_the_largest_page_and_resends_the_filter
    banks = [{ field: "number", operator: "start_with", value: "512" }]
    query = { filter: JSON.generate(banks), limit: "1000" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/ledger_accounts").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/ledger_accounts").with(query: query.merge(cursor: "c2"))
                                                .to_return(status: 200, body: page(2))

    assert_equal [1, 2], accounts.list(filter: banks).map { _1[:id] }.to_a
  end

  # names: getLedgerAccount
  def test_accounts_find
    stub_request(:get, "#{API}/ledger_accounts/7").to_return(status: 200, body: '{"id":7,"number":"512"}')

    assert_equal({ id: 7, number: "512" }, accounts.find(7))
  end

  # names: postLedgerAccounts
  def test_accounts_create
    stub_request(:post, "#{API}/ledger_accounts").with(body: '{"number":"6064","label":"Office supplies"}')
                                                 .to_return(status: 201, body: '{"id":8}')

    assert_equal({ id: 8 }, accounts.create(number: "6064", label: "Office supplies"))
  end

  # names: updateLedgerAccount
  def test_accounts_update_sends_only_the_given_attributes
    stub_request(:put, "#{API}/ledger_accounts/7").with(body: '{"letterable":true}')
                                                  .to_return(status: 200, body: '{"id":7}')

    assert_equal({ id: 7 }, accounts.update(7, letterable: true))
  end

  # names: getLedgerEntries
  def test_entries_list_walks_every_page_resending_the_filter
    march = [{ field: "date", operator: "gteq", value: "2026-03-01" }]
    query = { filter: JSON.generate(march), sort: "-date", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/ledger_entries").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/ledger_entries").with(query: query.merge(cursor: "c2"))
                                               .to_return(status: 200, body: page(2))

    assert_equal [1, 2], entries.list(filter: march, sort: "-date").map { _1[:id] }.to_a
  end

  # names: getLedgerEntry
  def test_entries_find
    stub_request(:get, "#{API}/ledger_entries/30").to_return(status: 200, body: '{"id":30,"label":"Rent"}')

    assert_equal({ id: 30, label: "Rent" }, entries.find(30))
  end

  # names: postLedgerEntries
  def test_entries_create_encodes_the_date_and_amounts
    body = { date: "2026-03-31", label: "Rent", journal_id: 4, ledger_entry_lines: SENT_LINES }
    stub_request(:post, "#{API}/ledger_entries").with(body: JSON.generate(body))
                                                .to_return(status: 201, body: '{"id":30}')

    amount = BigDecimal("1200.5")
    zero = BigDecimal(0)
    given = [{ debit: amount, credit: zero, ledger_account_id: 613 },
             { debit: zero, credit: amount, ledger_account_id: 512 }]

    assert_equal({ id: 30 }, entries.create(date: Date.new(2026, 3, 31), label: "Rent", journal_id: 4,
                                            ledger_entry_lines: given))
  end

  # names: putLedgerEntries
  def test_entries_update_takes_lines_as_create_update_delete
    lines = { update: [{ id: 91, label: "Rent, March" }], delete: [{ id: 92 }] }
    stub_request(:put, "#{API}/ledger_entries/30").with(body: JSON.generate({ ledger_entry_lines: lines }))
                                                  .to_return(status: 200, body: '{"id":30}')

    assert_equal({ id: 30 }, entries.update(30, ledger_entry_lines: lines))
  end

  # names: getLedgerEntriesLedgerEntryLines
  def test_entries_lines_walks_every_page
    stub_request(:get, "#{API}/ledger_entries/30/ledger_entry_lines")
      .with(query: { sort: "id", limit: "100" }).to_return(status: 200, body: page(91, 92))

    assert_equal [91, 92], entries.lines(30, sort: "id").map { _1[:id] }.to_a
  end
end
