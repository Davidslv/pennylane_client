# frozen_string_literal: true

require "test_helper"

# SEPA mandates: `client.sepa_mandates`. Each stub is the method and path
# from the operation's reference page.
class SepaMandatesTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def mandates = client.sepa_mandates

  def test_is_one_resource_per_client
    assert_same client.sepa_mandates, client.sepa_mandates
    refute_includes client.sepa_mandates.inspect, "tok"
  end

  # names: getSepaMandates
  def test_list_walks_every_page_resending_the_filter
    by_customer = [{ field: "customer_id", operator: "eq", value: "7" }]
    query = { filter: JSON.generate(by_customer), limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    last = JSON.generate({ items: [{ id: 2 }], has_more: false, next_cursor: nil })
    stub_request(:get, "#{API}/sepa_mandates").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/sepa_mandates").with(query: query.merge(cursor: "c2"))
                                              .to_return(status: 200, body: last)

    assert_equal [1, 2], mandates.list(filter: by_customer).map { _1[:id] }.to_a
  end

  # names: getSepaMandate
  def test_find
    stub_request(:get, "#{API}/sepa_mandates/3").to_return(status: 200, body: '{"id":3,"sequence_type":"RCUR"}')

    assert_equal({ id: 3, sequence_type: "RCUR" }, mandates.find(3))
  end

  # names: postSepaMandates
  def test_create
    stub_request(:post, "#{API}/sepa_mandates")
      .with(body: '{"customer_id":7,"iban":"FR7630006000011234567890189","bic":"AGRIFRPP",' \
                  '"identifier":"MANDATE-1","signed_at":"2026-09-01","sequence_type":"RCUR"}')
      .to_return(status: 201, body: '{"id":3}')

    assert_equal({ id: 3 }, mandates.create(customer_id: 7, iban: "FR7630006000011234567890189", bic: "AGRIFRPP",
                                            identifier: "MANDATE-1", signed_at: Date.new(2026, 9, 1),
                                            sequence_type: "RCUR"))
  end

  # names: putSepaMandate
  def test_update
    stub_request(:put, "#{API}/sepa_mandates/3").with(body: '{"sequence_type":"FNAL"}')
                                                .to_return(status: 200, body: '{"id":3}')

    assert_equal({ id: 3 }, mandates.update(3, sequence_type: "FNAL"))
  end

  # names: deleteSepaMandate
  def test_delete
    stub_request(:delete, "#{API}/sepa_mandates/3").with(body: nil).to_return(status: 204)

    assert mandates.delete(3)
  end
end
