# frozen_string_literal: true

require "test_helper"
require "bigdecimal"

# Bank transactions: `client.transactions`. Each stub is the method and
# path from the operation's reference page.
class TransactionsTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def transactions = client.transactions

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    assert_same client.transactions, client.transactions
    refute_includes client.transactions.inspect, "tok"
  end

  # names: getTransactions
  def test_list_walks_every_page_resending_the_filter
    in_account = [{ field: "bank_account_id", operator: "eq", value: "3" }]
    query = { filter: JSON.generate(in_account), sort: "id", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/transactions").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/transactions").with(query: query.merge(cursor: "c2"))
                                             .to_return(status: 200, body: page(2))

    assert_equal [1, 2], transactions.list(filter: in_account, sort: "id").map { _1[:id] }.to_a
  end

  # names: getTransaction
  def test_find
    stub_request(:get, "#{API}/transactions/9").to_return(status: 200, body: '{"id":9,"amount":"120.00"}')

    assert_equal({ id: 9, amount: "120.00" }, transactions.find(9))
  end

  # names: createTransaction
  def test_create_encodes_the_amount_and_date
    stub_request(:post, "#{API}/transactions")
      .with(body: '{"bank_account_id":3,"label":"Card payment","date":"2026-09-30","amount":"-12.5"}')
      .to_return(status: 201, body: '{"id":9}')

    assert_equal({ id: 9 }, transactions.create(bank_account_id: 3, label: "Card payment",
                                                date: Date.new(2026, 9, 30), amount: BigDecimal("-12.5")))
  end

  # names: updateTransaction
  def test_update_sets_the_third_party
    stub_request(:put, "#{API}/transactions/9").with(body: '{"supplier_id":12}')
                                               .to_return(status: 200, body: '{"id":9}')

    assert_equal({ id: 9 }, transactions.update(9, supplier_id: 12))
  end

  # names: getTransactionCategories
  def test_categories_walks_every_page
    stub_request(:get, "#{API}/transactions/9/categories").with(query: { limit: "100" })
                                                          .to_return(status: 200, body: page(1, 2))

    assert_equal [1, 2], transactions.categories(9).map { _1[:id] }.to_a
  end

  # names: putTransactionCategories
  def test_categorize_sends_the_categories_as_a_bare_array
    stub_request(:put, "#{API}/transactions/9/categories")
      .with(body: '[{"id":59,"weight":"0.5"},{"id":33,"weight":"0.5"},{"id":65,"weight":"1"}]')
      .to_return(status: 200, body: '[{"id":59},{"id":33},{"id":65}]')

    categories = [{ id: 59, weight: BigDecimal("0.5") }, { id: 33, weight: "0.5" }, { id: 65, weight: "1" }]

    assert_equal [{ id: 59 }, { id: 33 }, { id: 65 }], transactions.categorize(9, categories)
  end

  # names: getTransactionMatchedInvoices
  def test_matched_invoices_walks_every_page
    stub_request(:get, "#{API}/transactions/9/matched_invoices").with(query: { limit: "100" })
                                                                .to_return(status: 200, body: page(42, 43))

    assert_equal [42, 43], transactions.matched_invoices(9).map { _1[:id] }.to_a
  end
end
