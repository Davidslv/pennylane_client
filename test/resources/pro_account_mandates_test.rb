# frozen_string_literal: true

require "test_helper"

# Pro Account mandates: `client.pro_account_mandates`. Each stub is the
# method and path from the operation's reference page.
class ProAccountMandatesTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def mandates = client.pro_account_mandates

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    assert_same client.pro_account_mandates, client.pro_account_mandates
    refute_includes client.pro_account_mandates.inspect, "tok"
  end

  # names: getProAccountMandates
  def test_list_walks_every_page_resending_the_filter
    active = [{ field: "status", operator: "eq", value: "active" }]
    query = { filter: JSON.generate(active), limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/pro_account/mandates").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/pro_account/mandates").with(query: query.merge(cursor: "c2"))
                                                     .to_return(status: 200, body: page(2))

    assert_equal [1, 2], mandates.list(filter: active).map { _1[:id] }.to_a
  end

  # names: postProAccountMandateMailRequests
  def test_send_request_returns_true
    stub_request(:post, "#{API}/pro_account/mandate_requests").with(body: '{"customer_id":7}')
                                                              .to_return(status: 201, body: "")

    assert_same true, mandates.send_request(customer_id: 7)
  end

  # names: getProAccountMandateMigrations
  def test_migration_candidates_walks_every_page
    stub_request(:get, "#{API}/pro_account/mandate_migrations").with(query: { limit: "100" })
                                                               .to_return(status: 200, body: page(1, 2))

    assert_equal [1, 2], mandates.migration_candidates.map { _1[:id] }.to_a
  end

  # names: postProAccountMandateMigrations
  def test_migrate
    stub_request(:post, "#{API}/pro_account/mandate_migrations")
      .with(body: '{"mandate_type":"SepaMandate","mandate_id":3,"early_execution_date_permitted":true}')
      .to_return(status: 201, body: '{"mandate_migration":{"id":11}}')

    migration = mandates.migrate(mandate_type: "SepaMandate", mandate_id: 3, early_execution_date_permitted: true)

    assert_equal({ mandate_migration: { id: 11 } }, migration)
  end

  def test_migrate_without_the_mandate_raises_before_any_request
    assert_raises(ArgumentError) { mandates.migrate(mandate_type: "Mandate") }
    assert_not_requested :any, /pro_account/
  end

  # Pennylane answers 404 without a Pro Account, 403 without an enabled
  # merchant profile.
  def test_a_company_without_a_pro_account_or_merchant_profile_raises
    no_pro_account = { status: 404, body: "{}" }
    no_merchant_profile = { status: 403, body: "{}" }
    stub_request(:get, "#{API}/pro_account/mandates").with(query: { limit: "100" })
                                                     .to_return(no_pro_account, no_merchant_profile)

    assert_raises(PennylaneClient::NotFoundError) { mandates.list.first }
    assert_raises(PennylaneClient::PermissionError) { mandates.list.first }
  end
end
