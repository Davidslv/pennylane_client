# frozen_string_literal: true

require "test_helper"
require "date"

# Trial balance: `client.trial_balance`. The stub is the method and path
# from the operation's reference page.
class TrialBalanceTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"
  YEAR = [Date.new(2026, 1, 1), Date.new(2026, 12, 31)].freeze

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def trial_balance = client.trial_balance

  # One page of accounts by number, with the cursor to the next.
  def page(number, cursor) = JSON.generate({ items: [{ number: }], has_more: !cursor.nil?, next_cursor: cursor })

  def stub_page(query, body)
    stub_request(:get, "#{API}/trial_balance").with(query:).to_return(status: 200, body:)
  end

  def test_is_one_resource_per_client
    assert_same client.trial_balance, client.trial_balance
    refute_includes client.trial_balance.inspect, "tok"
  end

  # names: getTrialBalance
  def test_list_encodes_the_period_and_walks_every_page
    query = { period_start: "2026-01-01", period_end: "2026-12-31", is_auxiliary: "true", limit: "1000" }
    stub_page(query, page("401", "c2"))
    stub_page(query.merge(cursor: "c2"), page("512", nil))

    accounts = trial_balance.list(period_start: YEAR.first, period_end: YEAR.last, is_auxiliary: true)

    assert_equal %w[401 512], accounts.map { _1[:number] }.to_a
  end

  def test_list_requires_the_period
    assert_raises(ArgumentError) { trial_balance.list(period_start: "2026-01-01") }
  end
end
