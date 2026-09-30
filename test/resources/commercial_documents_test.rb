# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "date"

# Commercial documents (proforma, shipping and purchasing orders):
# `client.commercial_documents`. Each stub is the method and path from the
# operation's reference page.
class CommercialDocumentsTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def documents = client.commercial_documents

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    assert_same client.commercial_documents, client.commercial_documents
    refute_includes client.commercial_documents.inspect, "tok"
  end

  # names: listCommercialDocuments
  def test_list_walks_every_page_resending_the_filter
    proformas = [{ field: "document_type", operator: "eq", value: "proforma" }]
    query = { filter: JSON.generate(proformas), sort: "-id", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/commercial_documents").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/commercial_documents").with(query: query.merge(cursor: "c2"))
                                                     .to_return(status: 200, body: page(2))

    assert_equal [1, 2], documents.list(filter: proformas, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getCommercialDocument
  def test_find
    stub_request(:get, "#{API}/commercial_documents/5")
      .to_return(status: 200, body: '{"id":5,"document_type":"proforma"}')

    assert_equal({ id: 5, document_type: "proforma" }, documents.find(5))
  end

  # names: postCommercialDocuments
  def test_create_encodes_the_dates_and_amounts
    body = { document_type: "shipping_order", customer_id: 7, date: "2026-09-30", deadline: "2026-10-30",
             invoice_lines: [{ label: "Crate", quantity: 3, raw_currency_unit_price: "19.9", unit: "piece",
                               vat_rate: "FR_200" }] }
    stub_request(:post, "#{API}/commercial_documents").with(body: JSON.generate(body))
                                                      .to_return(status: 201, body: '{"id":5}')

    assert_equal({ id: 5 }, documents.create(document_type: "shipping_order", customer_id: 7,
                                             date: Date.new(2026, 9, 30), deadline: Date.new(2026, 10, 30),
                                             invoice_lines: [{ label: "Crate", quantity: 3,
                                                               raw_currency_unit_price: BigDecimal("19.9"),
                                                               unit: "piece", vat_rate: "FR_200" }]))
  end

  # names: updateCommercialDocument
  def test_update_sends_only_the_given_attributes
    stub_request(:put, "#{API}/commercial_documents/5")
      .with(body: '{"invoice_lines":{"delete":[{"id":31}]}}')
      .to_return(status: 200, body: '{"id":5}')

    assert_equal({ id: 5 }, documents.update(5, invoice_lines: { delete: [{ id: 31 }] }))
  end

  # names: getCommercialDocumentInvoiceLines
  def test_invoice_lines_walks_every_page
    stub_request(:get, "#{API}/commercial_documents/5/invoice_lines").with(query: { sort: "-id", limit: "100" })
                                                                     .to_return(status: 200, body: page(1, 2))

    assert_equal [1, 2], documents.invoice_lines(5, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getCommercialDocumentInvoiceLineSections
  def test_invoice_line_sections_walks_every_page
    stub_request(:get, "#{API}/commercial_documents/5/invoice_line_sections").with(query: { limit: "100" })
                                                                             .to_return(status: 200, body: page(1, 2))

    assert_equal [1, 2], documents.invoice_line_sections(5).map { _1[:id] }.to_a
  end

  # names: getCommercialDocumentAppendices
  def test_appendices_walks_every_page
    stub_request(:get, "#{API}/commercial_documents/5/appendices").with(query: { limit: "10" })
                                                                  .to_return(status: 200, body: page(1, 2))

    assert_equal [1, 2], documents.appendices(5, limit: 10).map { _1[:id] }.to_a
  end

  # names: postCommercialDocumentAppendices
  def test_upload_appendix_streams_the_file
    file_part = %(name="file"; filename="plan.png"\r\nContent-Type: image/png\r\n\r\nPNG)
    stub_request(:post, "#{API}/commercial_documents/5/appendices").with do |request|
      request.headers["Content-Type"].start_with?("multipart/form-data; boundary=") && request.body.include?(file_part)
    end.to_return(status: 201, body: '{"id":8}')

    file = PennylaneClient::Upload.new(StringIO.new("PNG"), filename: "plan.png")

    assert_equal({ id: 8 }, documents.upload_appendix(5, file))
  end
end
