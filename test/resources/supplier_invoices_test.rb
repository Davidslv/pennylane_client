# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "date"

# Shared by the Supplier Invoices behaviour tests: a real Client, with
# WebMock as Pennylane. Each stub is the method and path from the
# operation's reference page.
module SupplierInvoicesTestHelper
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def invoices = client.supplier_invoices

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })
end

# The invoice itself: list, find, update, validate.
class SupplierInvoicesTest < Minitest::Test
  include SupplierInvoicesTestHelper

  def test_is_one_resource_per_client
    assert_same client.supplier_invoices, client.supplier_invoices
    refute_includes client.supplier_invoices.inspect, "tok"
  end

  # names: getSupplierInvoices
  def test_list_walks_every_page_resending_the_filter
    unpaid = [{ field: "payment_status", operator: "eq", value: "to_be_paid" }]
    query = { filter: JSON.generate(unpaid), sort: "-id", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/supplier_invoices").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/supplier_invoices").with(query: query.merge(cursor: "c2"))
                                                  .to_return(status: 200, body: page(2))

    assert_equal [1, 2], invoices.list(filter: unpaid, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getSupplierInvoice
  def test_find
    stub_request(:get, "#{API}/supplier_invoices/42").to_return(status: 200, body: '{"id":42,"label":"Rent"}')

    assert_equal({ id: 42, label: "Rent" }, invoices.find(42))
  end

  # names: putSupplierInvoice
  def test_update
    stub_request(:put, "#{API}/supplier_invoices/42")
      .with(body: '{"deadline":"2026-11-30","invoice_lines":{"delete":[{"id":3}]}}')
      .to_return(status: 200, body: '{"id":42}')

    assert_equal({ id: 42 }, invoices.update(42, deadline: Date.new(2026, 11, 30),
                                                 invoice_lines: { delete: [{ id: 3 }] }))
  end

  # names: ValidateAccountingSupplierInvoice
  def test_validate_accounting_sends_no_body
    stub_request(:put, "#{API}/supplier_invoices/42/validate_accounting")
      .with(body: nil)
      .to_return(status: 200, body: '{"id":42,"accounting_status":"complete"}')

    assert_equal({ id: 42, accounting_status: "complete" }, invoices.validate_accounting(42))
  end

  def test_a_failure_raises_its_error
    stub_request(:get, "#{API}/supplier_invoices/404").to_return(status: 404, body: '{"error":"not_found"}')

    assert_raises(PennylaneClient::NotFoundError) { invoices.find(404) }
  end
end

# The two ways a supplier invoice comes to exist: imported with a file
# already uploaded, or imported from an e-invoice file.
class SupplierInvoiceImportsTest < Minitest::Test
  include SupplierInvoicesTestHelper

  # Every field importSupplierInvoice requires, amounts that add up.
  IMPORTED = {
    file_attachment_id: 5, supplier_id: 12, date: "2026-09-30", deadline: "2026-10-30",
    currency_amount_before_tax: "100.5", currency_amount: "120.6", currency_tax: "20.1",
    invoice_lines: [{ currency_amount: "120.6", currency_tax: "20.1", vat_rate: "FR_200" }]
  }.freeze

  # names: importSupplierInvoice
  def test_import_encodes_dates_and_amounts
    stub_request(:post, "#{API}/supplier_invoices/import")
      .with(body: JSON.generate(IMPORTED))
      .to_return(status: 201, body: '{"id":45}')

    line = { currency_amount: BigDecimal("120.6"), currency_tax: BigDecimal("20.1"), vat_rate: "FR_200" }

    assert_equal({ id: 45 }, invoices.import(file_attachment_id: 5, supplier_id: 12, date: Date.new(2026, 9, 30),
                                             deadline: Date.new(2026, 10, 30),
                                             currency_amount_before_tax: BigDecimal("100.5"),
                                             currency_amount: BigDecimal("120.6"), currency_tax: BigDecimal("20.1"),
                                             invoice_lines: [line]))
  end

  # Pennylane de-duplicates imported files: the same file twice is a 409.
  def test_import_of_a_duplicate_file_raises_conflict
    stub_request(:post, "#{API}/supplier_invoices/import")
      .to_return(status: 409, body: '{"status":409,"error":"Resource already exists."}')

    error = assert_raises(PennylaneClient::ConflictError) { invoices.import(**IMPORTED) }
    assert_includes error.message, "already exists"
  end

  # names: createSupplierInvoiceEInvoiceImport
  def test_import_e_invoice_uploads_the_file_with_json_options
    file_part = %(name="file"; filename="invoice.xml"\r\nContent-Type: application/xml\r\n\r\n<Invoice/>)
    options_part = %(name="invoice_options"\r\nContent-Type: application/json\r\n\r\n{"supplier_id":12})
    stub_request(:post, "#{API}/supplier_invoices/e_invoices/imports").with do |request|
      request.headers["Content-Type"].start_with?("multipart/form-data; boundary=") &&
        request.body.include?(file_part) && request.body.include?(options_part)
    end.to_return(status: 201, body: '{"id":46}')

    xml = PennylaneClient::Upload.new(StringIO.new("<Invoice/>"), filename: "invoice.xml")

    assert_equal({ id: 46 }, invoices.import_e_invoice(xml, invoice_options: { supplier_id: 12 }))
  end
end

# What changes on an invoice after it exists: payment status, e-invoice
# status, categories, linked purchase requests, matched transactions.
class SupplierInvoiceActionsTest < Minitest::Test
  include SupplierInvoicesTestHelper

  # names: updateSupplierInvoicePaymentStatus
  def test_update_payment_status_returns_true_on_no_content
    stub_request(:put, "#{API}/supplier_invoices/42/payment_status")
      .with(body: '{"payment_status":"paid"}')
      .to_return(status: 204)

    assert_same true, invoices.update_payment_status(42, payment_status: "paid")
  end

  # names: putSupplierInvoiceEInvoiceStatus
  def test_update_e_invoice_status_disputes_with_a_reason
    stub_request(:put, "#{API}/supplier_invoices/42/e_invoice_status")
      .with(body: '{"status":"disputed","reason":"incorrect_vat_rate"}')
      .to_return(status: 200, body: '{"id":42}')

    assert_equal({ id: 42 }, invoices.update_e_invoice_status(42, status: "disputed", reason: "incorrect_vat_rate"))
  end

  def test_update_e_invoice_status_undisputes_with_no_reason
    stub_request(:put, "#{API}/supplier_invoices/42/e_invoice_status")
      .with(body: '{"status":"approved"}')
      .to_return(status: 200, body: '{"id":42}')

    assert_equal({ id: 42 }, invoices.update_e_invoice_status(42, status: "approved"))
  end

  def test_update_e_invoice_status_requires_a_status
    assert_raises(ArgumentError) { invoices.update_e_invoice_status(42, reason: "delivery_issue") }
  end

  # names: postSupplierInvoiceLinkedPurchaseRequests
  def test_link_purchase_request_returns_true_on_no_content
    stub_request(:post, "#{API}/supplier_invoices/42/linked_purchase_requests")
      .with(body: '{"purchase_request_id":8}')
      .to_return(status: 204)

    assert_same true, invoices.link_purchase_request(42, purchase_request_id: 8)
  end

  # names: postSupplierInvoiceMatchedTransactions
  def test_match_transaction_returns_true_on_no_content
    stub_request(:post, "#{API}/supplier_invoices/42/matched_transactions")
      .with(body: '{"transaction_id":9}')
      .to_return(status: 204)

    assert_same true, invoices.match_transaction(42, transaction_id: 9)
  end

  # names: deleteSupplierInvoiceMatchedTransactions
  def test_unmatch_transaction_returns_true_on_no_content
    stub_request(:delete, "#{API}/supplier_invoices/42/matched_transactions/9").with(body: nil).to_return(status: 204)

    assert_same true, invoices.unmatch_transaction(42, transaction_id: 9)
  end

  # The same shape as match_transaction: the transaction is a keyword. A
  # positional id raises instead of reaching Pennylane.
  def test_unmatch_transaction_takes_the_transaction_as_a_keyword
    assert_raises(ArgumentError) { invoices.unmatch_transaction(42, 9) }
  end

  # names: putSupplierInvoiceCategories
  def test_categorize_sends_the_categories_as_a_bare_array
    stub_request(:put, "#{API}/supplier_invoices/42/categories")
      .with(body: '[{"id":426,"weight":"0.6575"},{"id":427,"weight":"0.3425"}]')
      .to_return(status: 200, body: '[{"id":426},{"id":427}]')

    categories = [{ id: 426, weight: BigDecimal("0.6575") }, { id: 427, weight: "0.3425" }]

    assert_equal [{ id: 426 }, { id: 427 }], invoices.categorize(42, categories)
  end
end

# What hangs off one invoice. Every list here is paginated, so each walks
# all its pages at the largest page size.
class SupplierInvoiceNestedTest < Minitest::Test
  include SupplierInvoicesTestHelper

  def stub_list(path, **query)
    stub_request(:get, "#{API}/supplier_invoices/42/#{path}")
      .with(query: { limit: "100", **query })
      .to_return(status: 200, body: page(1, 2))
  end

  # names: getSupplierInvoiceLines
  def test_invoice_lines_walks_every_page
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/supplier_invoices/42/invoice_lines")
      .with(query: { limit: "100", sort: "id" })
      .to_return(status: 200, body: first)
    stub_request(:get, "#{API}/supplier_invoices/42/invoice_lines")
      .with(query: { limit: "100", sort: "id", cursor: "c2" })
      .to_return(status: 200, body: page(2))

    assert_equal [1, 2], invoices.invoice_lines(42, sort: "id").map { _1[:id] }.to_a
  end

  # names: getSupplierInvoicePayments
  def test_payments
    stub_list("payments", sort: "-id")

    assert_equal [1, 2], invoices.payments(42, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getSupplierInvoiceMatchedTransactions
  def test_matched_transactions
    stub_list("matched_transactions")

    assert_equal [1, 2], invoices.matched_transactions(42).map { _1[:id] }.to_a
  end

  # names: getSupplierInvoiceCategories
  def test_categories
    stub_list("categories")

    assert_equal [1, 2], invoices.categories(42).map { _1[:id] }.to_a
  end
end
