# frozen_string_literal: true

require "test_helper"

# Bank accounts and bank establishments: `client.bank_accounts` and
# `client.bank_establishments`. Each stub is the method and path from the
# operation's reference page.
class BankAccountsTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def accounts = client.bank_accounts

  # Two pages at `path`, ids `first` then `last`; `query` must come back
  # on both.
  def stub_two_pages(path, query, first, last)
    stub_request(:get, "#{API}/#{path}").with(query:)
                                        .to_return(status: 200, body: page(first, "c2"))
    stub_request(:get, "#{API}/#{path}").with(query: query.merge(cursor: "c2"))
                                        .to_return(status: 200, body: page(last))
  end

  def page(id, next_cursor = nil)
    JSON.generate({ items: [{ id: }], has_more: !next_cursor.nil?, next_cursor: })
  end

  def test_is_one_resource_per_client
    %i[bank_accounts bank_establishments].each do |name|
      assert_same client.public_send(name), client.public_send(name)
      refute_includes client.public_send(name).inspect, "tok"
    end
  end

  # names: getBankAccounts
  def test_list_walks_every_page_resending_the_sort
    stub_two_pages("bank_accounts", { sort: "id", limit: "100" }, 1, 2)

    assert_equal [1, 2], accounts.list(sort: "id").map { _1[:id] }.to_a
  end

  # names: getBankAccount
  def test_find
    stub_request(:get, "#{API}/bank_accounts/3").to_return(status: 200, body: '{"id":3,"balance":"100.15"}')

    assert_equal({ id: 3, balance: "100.15" }, accounts.find(3))
  end

  # names: postBankAccount
  def test_create
    stub_request(:post, "#{API}/bank_accounts")
      .with(body: '{"name":"Main account","iban":"FR7630006000011234567890189","currency":"EUR"}')
      .to_return(status: 201, body: '{"id":3}')

    assert_equal({ id: 3 }, accounts.create(name: "Main account", iban: "FR7630006000011234567890189",
                                            currency: "EUR"))
  end

  # names: getBankEstablishments
  def test_bank_establishments_list_walks_every_page_resending_the_filter
    by_id = [{ field: "id", operator: "gt", value: "40" }]
    stub_two_pages("bank_establishments", { filter: JSON.generate(by_id), limit: "100" }, 41, 42)

    assert_equal [41, 42], client.bank_establishments.list(filter: by_id).map { _1[:id] }.to_a
  end
end
