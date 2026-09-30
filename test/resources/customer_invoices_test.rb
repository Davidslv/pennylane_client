# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "date"

# Shared by the Customer Invoices behaviour tests: a real Client, with
# WebMock as Pennylane. Each stub is the method and path from the
# operation's reference page.
module CustomerInvoicesTestHelper
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def invoices = client.customer_invoices

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })
end

# The invoice itself: list, find, create, update, delete.
class CustomerInvoicesTest < Minitest::Test
  include CustomerInvoicesTestHelper

  def test_is_one_resource_per_client
    assert_same client.customer_invoices, client.customer_invoices
    refute_includes client.customer_invoices.inspect, "tok"
  end

  # names: getCustomerInvoices
  def test_list_walks_every_page_resending_the_filter
    drafts = [{ field: "status", operator: "eq", value: "draft" }]
    query = { filter: JSON.generate(drafts), sort: "-id", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/customer_invoices").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/customer_invoices").with(query: query.merge(cursor: "c2"))
                                                  .to_return(status: 200, body: page(2))

    assert_equal [1, 2], invoices.list(filter: drafts, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getCustomerInvoice
  def test_find
    stub_request(:get, "#{API}/customer_invoices/42").to_return(status: 200, body: '{"id":42,"status":"draft"}')

    assert_equal({ id: 42, status: "draft" }, invoices.find(42))
  end

  # names: postCustomerInvoices
  def test_create_sends_the_attributes_as_the_json_body
    body = { customer_id: 7, date: "2026-09-30", deadline: "2026-10-30", draft: true,
             invoice_lines: [{ label: "Audit", quantity: 1, raw_currency_unit_price: "100.5", unit: "day",
                               vat_rate: "FR_200" }] }
    stub_request(:post, "#{API}/customer_invoices").with(body: JSON.generate(body))
                                                   .to_return(status: 201, body: '{"id":43}')

    assert_equal({ id: 43 }, invoices.create(customer_id: 7, date: Date.new(2026, 9, 30),
                                             deadline: Date.new(2026, 10, 30), draft: true,
                                             invoice_lines: [{ label: "Audit", quantity: 1,
                                                               raw_currency_unit_price: BigDecimal("100.5"),
                                                               unit: "day", vat_rate: "FR_200" }]))
  end

  # names: updateCustomerInvoice
  def test_update
    stub_request(:put, "#{API}/customer_invoices/42").with(body: '{"pdf_description":"Q3"}')
                                                     .to_return(status: 200, body: '{"id":42}')

    assert_equal({ id: 42 }, invoices.update(42, pdf_description: "Q3"))
  end

  # names: deleteCustomerInvoices
  def test_delete_returns_true_on_no_content
    stub_request(:delete, "#{API}/customer_invoices/42").to_return(status: 204)

    assert invoices.delete(42)
  end

  def test_a_failure_raises_its_error
    stub_request(:get, "#{API}/customer_invoices/404").to_return(status: 404, body: '{"error":"not_found"}')

    assert_raises(PennylaneClient::NotFoundError) { invoices.find(404) }
  end
end
