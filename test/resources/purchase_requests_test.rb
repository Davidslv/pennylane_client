# frozen_string_literal: true

require "test_helper"

# Purchase requests: `client.purchase_requests`. Each stub is the method
# and path from the operation's reference page.
class PurchaseRequestsTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def requests = client.purchase_requests

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    assert_same client.purchase_requests, client.purchase_requests
    refute_includes client.purchase_requests.inspect, "tok"
  end

  # names: getPurchaseRequests
  def test_list_walks_every_page_resending_the_filter
    by_supplier = [{ field: "supplier_id", operator: "eq", value: "4" }]
    query = { filter: JSON.generate(by_supplier), limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/purchase_requests").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/purchase_requests").with(query: query.merge(cursor: "c2"))
                                                  .to_return(status: 200, body: page(2))

    assert_equal [1, 2], requests.list(filter: by_supplier).map { _1[:id] }.to_a
  end

  # names: getPurchaseRequest
  def test_find
    stub_request(:get, "#{API}/purchase_requests/9").to_return(status: 200, body: '{"id":9,"status":"approved"}')

    assert_equal({ id: 9, status: "approved" }, requests.find(9))
  end

  # names: createPurchaseRequestImport
  def test_import_sends_json_with_the_file_attachment_id_and_encoded_amounts
    body = '{"file_attachment_id":12,"supplier_id":4,"currency_amount":"120.0","estimated_delivery_date":"2026-11-02"}'
    json = { "Content-Type" => "application/json" }
    stub_request(:post, "#{API}/purchase_requests/imports").with(body:, headers: json)
                                                           .to_return(status: 201, body: '{"id":9}')

    imported = requests.import(file_attachment_id: 12, supplier_id: 4, currency_amount: BigDecimal("120"),
                               estimated_delivery_date: Date.new(2026, 11, 2))

    assert_equal({ id: 9 }, imported)
  end
end
