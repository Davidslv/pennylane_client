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

# What happens to an invoice after it exists: finalize, pay, send, link.
class CustomerInvoiceActionsTest < Minitest::Test
  include CustomerInvoicesTestHelper

  # names: finalizeCustomerInvoice
  def test_finalize_sends_no_body
    stub_request(:put, "#{API}/customer_invoices/42/finalize")
      .with(body: nil)
      .to_return(status: 200, body: '{"id":42,"status":"upcoming"}')

    assert_equal({ id: 42, status: "upcoming" }, invoices.finalize(42))
  end

  # names: markAsPaidCustomerInvoice
  def test_mark_as_paid
    stub_request(:put, "#{API}/customer_invoices/42/mark_as_paid").to_return(status: 204)

    assert invoices.mark_as_paid(42)
  end

  # names: markAsPaidCustomerInvoiceInstallment
  def test_mark_installment_as_paid
    stub_request(:put, "#{API}/customer_invoices/42/installments/3/mark_as_paid").to_return(status: 204)

    assert invoices.mark_installment_as_paid(42, 3)
  end

  # names: sendByEmailCustomerInvoice
  def test_send_by_email_to_given_recipients
    stub_request(:post, "#{API}/customer_invoices/42/send_by_email")
      .with(body: '{"recipients":["billing@example.com"]}').to_return(status: 204)

    assert invoices.send_by_email(42, recipients: ["billing@example.com"])
  end

  def test_send_by_email_to_the_customer_by_default
    stub_request(:post, "#{API}/customer_invoices/42/send_by_email").with(body: "{}").to_return(status: 204)

    assert invoices.send_by_email(42)
  end

  # Pennylane answers 409 while the PDF is still being generated.
  def test_send_by_email_before_the_pdf_exists_raises_conflict
    stub_request(:post, "#{API}/customer_invoices/42/send_by_email").to_return(status: 409, body: "{}")

    assert_raises(PennylaneClient::ConflictError) { invoices.send_by_email(42) }
  end

  # names: sendToPaCustomerInvoice
  def test_send_to_pa
    stub_request(:post, "#{API}/customer_invoices/42/send_to_pa").with(body: nil).to_return(status: 204)

    assert invoices.send_to_pa(42)
  end

  # names: linkCreditNote
  def test_link_credit_note
    stub_request(:post, "#{API}/customer_invoices/42/link_credit_note")
      .with(body: '{"credit_note_id":43}')
      .to_return(status: 200, body: '{"id":42}')

    assert_equal({ id: 42 }, invoices.link_credit_note(42, 43))
  end

  # names: updateImportedCustomerInvoice
  def test_update_imported
    stub_request(:put, "#{API}/customer_invoices/42/update_imported")
      .with(body: '{"invoice_number":"F-7"}')
      .to_return(status: 200, body: '{"id":42}')

    assert_equal({ id: 42 }, invoices.update_imported(42, invoice_number: "F-7"))
  end
end

# The other ways an invoice comes to exist: from a quote, imported with a
# file already uploaded, or imported from an e-invoice file.
class CustomerInvoiceImportsTest < Minitest::Test
  include CustomerInvoicesTestHelper

  # names: createCustomerInvoiceFromQuote
  def test_create_from_quote
    stub_request(:post, "#{API}/customer_invoices/create_from_quote")
      .with(body: '{"quote_id":9,"draft":true}')
      .to_return(status: 201, body: '{"id":44}')

    assert_equal({ id: 44 }, invoices.create_from_quote(quote_id: 9, draft: true))
  end

  # names: importCustomerInvoices
  def test_import
    body = { file_attachment_id: 5, customer_id: 7, invoice_number: "F-1", date: "2026-09-30",
             currency_amount: "120.0" }
    stub_request(:post, "#{API}/customer_invoices/import")
      .with(body: JSON.generate(body))
      .to_return(status: 201, body: '{"id":45}')

    assert_equal({ id: 45 }, invoices.import(file_attachment_id: 5, customer_id: 7, invoice_number: "F-1",
                                             date: Date.new(2026, 9, 30), currency_amount: BigDecimal("120")))
  end

  # names: createCustomerInvoiceEInvoiceImport
  def test_import_e_invoice_uploads_the_file_with_json_options
    file_part = %(name="file"; filename="invoice.xml"\r\nContent-Type: application/xml\r\n\r\n<Invoice/>)
    options_part = %(name="invoice_options"\r\nContent-Type: application/json\r\n\r\n{"customer_id":12})
    stub_request(:post, "#{API}/customer_invoices/e_invoices/imports").with do |request|
      request.headers["Content-Type"].start_with?("multipart/form-data; boundary=") &&
        request.body.include?(file_part) && request.body.include?(options_part)
    end.to_return(status: 201, body: '{"id":46}')

    xml = PennylaneClient::Upload.new(StringIO.new("<Invoice/>"), filename: "invoice.xml")

    assert_equal({ id: 46 }, invoices.import_e_invoice(xml, invoice_options: { customer_id: 12 }))
  end
end

# What hangs off one invoice. Every list here is paginated, so each walks
# all its pages at the largest page size.
class CustomerInvoiceNestedTest < Minitest::Test
  include CustomerInvoicesTestHelper

  def stub_list(path, **query)
    stub_request(:get, "#{API}/customer_invoices/42/#{path}")
      .with(query: { limit: "100", **query })
      .to_return(status: 200, body: page(1, 2))
  end

  # names: getCustomerInvoiceInvoiceLines
  def test_invoice_lines_walks_every_page
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/customer_invoices/42/invoice_lines")
      .with(query: { limit: "100", sort: "id" })
      .to_return(status: 200, body: first)
    stub_request(:get, "#{API}/customer_invoices/42/invoice_lines")
      .with(query: { limit: "100", sort: "id", cursor: "c2" })
      .to_return(status: 200, body: page(2))

    assert_equal [1, 2], invoices.invoice_lines(42, sort: "id").map { _1[:id] }.to_a
  end

  # names: getCustomerInvoiceInvoiceLineSections
  def test_invoice_line_sections
    stub_list("invoice_line_sections")

    assert_equal [1, 2], invoices.invoice_line_sections(42).map { _1[:id] }.to_a
  end

  # names: getCustomerInvoicePayments
  def test_payments
    stub_list("payments", sort: "-id")

    assert_equal [1, 2], invoices.payments(42, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getCustomerInvoiceMatchedTransactions
  def test_matched_transactions
    stub_list("matched_transactions")

    assert_equal [1, 2], invoices.matched_transactions(42).map { _1[:id] }.to_a
  end

  # names: getCustomerInvoiceCustomHeaderFields
  def test_custom_header_fields
    stub_list("custom_header_fields")

    assert_equal [1, 2], invoices.custom_header_fields(42).map { _1[:id] }.to_a
  end

  # names: getCustomerInvoiceAppendices
  def test_appendices
    stub_list("appendices", limit: "10")

    assert_equal [1, 2], invoices.appendices(42, limit: 10).map { _1[:id] }.to_a
  end

  # names: postCustomerInvoiceAppendices
  def test_upload_appendix_streams_the_file
    stub_request(:post, "#{API}/customer_invoices/42/appendices")
      .with { _1.body.include?(%(name="file"; filename="terms.pdf"\r\nContent-Type: application/pdf\r\n\r\n%PDF-1.7)) }
      .to_return(status: 201, body: '{"id":8}')

    file = PennylaneClient::Upload.new(StringIO.new("%PDF-1.7"), filename: "terms.pdf")

    assert_equal({ id: 8 }, invoices.upload_appendix(42, file))
  end

  # names: getCustomerInvoiceCategories
  def test_categories
    stub_list("categories")

    assert_equal [1, 2], invoices.categories(42).map { _1[:id] }.to_a
  end

  # names: putCustomerInvoiceCategories
  def test_categorize_sends_the_categories_as_a_bare_array
    stub_request(:put, "#{API}/customer_invoices/42/categories")
      .with(body: '[{"id":426,"weight":"0.6575"},{"id":427,"weight":"0.3425"}]')
      .to_return(status: 200, body: '[{"id":426},{"id":427}]')

    categories = [{ id: 426, weight: BigDecimal("0.6575") }, { id: 427, weight: "0.3425" }]

    assert_equal [{ id: 426 }, { id: 427 }], invoices.categorize(42, categories)
  end
end
