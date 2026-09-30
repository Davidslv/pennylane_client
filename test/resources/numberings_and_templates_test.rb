# frozen_string_literal: true

require "test_helper"

# Document numberings and customer invoice templates, two read-only lists:
# `client.numberings` and `client.customer_invoice_templates`. Each stub is
# the method and path from the operation's reference page.
class NumberingsAndTemplatesTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)

  def test_numberings_is_one_resource_per_client
    assert_same client.numberings, client.numberings
    refute_includes client.numberings.inspect, "tok"
  end

  def test_customer_invoice_templates_is_one_resource_per_client
    assert_same client.customer_invoice_templates, client.customer_invoice_templates
    refute_includes client.customer_invoice_templates.inspect, "tok"
  end

  # names: getNumberings
  def test_numberings_walks_every_page
    first = JSON.generate({ items: [{ id: 1, document_type: "invoice" }], has_more: true, next_cursor: "c2" })
    last = JSON.generate({ items: [{ id: 2, document_type: "estimate" }], has_more: false, next_cursor: nil })
    stub_request(:get, "#{API}/numberings").with(query: { sort: "id", limit: "100" })
                                           .to_return(status: 200, body: first)
    stub_request(:get, "#{API}/numberings").with(query: { sort: "id", limit: "100", cursor: "c2" })
                                           .to_return(status: 200, body: last)

    assert_equal %w[invoice estimate], client.numberings.list(sort: "id").map { _1[:document_type] }.to_a
  end

  # names: getCustomerInvoiceTemplates
  def test_customer_invoice_templates_walks_every_page
    stub_request(:get, "#{API}/customer_invoice_templates").with(query: { limit: "100" })
                                                           .to_return(status: 200, body: JSON.generate(
                                                             { items: [{ id: 3 }], has_more: false, next_cursor: nil }
                                                           ))

    assert_equal [3], client.customer_invoice_templates.list.map { _1[:id] }.to_a
  end
end
