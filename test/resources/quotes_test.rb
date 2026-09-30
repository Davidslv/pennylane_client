# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "date"

# Quotes: `client.quotes`. Each stub is the method and path from the
# operation's reference page.
class QuotesTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def quotes = client.quotes

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    assert_same client.quotes, client.quotes
    refute_includes client.quotes.inspect, "tok"
  end

  # names: listQuotes
  def test_list_walks_every_page_resending_the_filter
    pending = [{ field: "status", operator: "eq", value: "pending" }]
    query = { filter: JSON.generate(pending), sort: "-id", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/quotes").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/quotes").with(query: query.merge(cursor: "c2")).to_return(status: 200, body: page(2))

    assert_equal [1, 2], quotes.list(filter: pending, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getQuote
  def test_find
    stub_request(:get, "#{API}/quotes/9").to_return(status: 200, body: '{"id":9,"status":"pending"}')

    assert_equal({ id: 9, status: "pending" }, quotes.find(9))
  end

  # names: postQuotes
  def test_create_encodes_the_dates_and_amounts
    body = { customer_id: 7, date: "2026-09-30", deadline: "2026-10-30",
             invoice_lines: [{ label: "Audit", quantity: 2, raw_currency_unit_price: "450.5", unit: "day",
                               vat_rate: "FR_200" }] }
    stub_request(:post, "#{API}/quotes").with(body: JSON.generate(body)).to_return(status: 201, body: '{"id":9}')

    assert_equal({ id: 9 }, quotes.create(customer_id: 7, date: Date.new(2026, 9, 30), deadline: Date.new(2026, 10, 30),
                                          invoice_lines: [{ label: "Audit", quantity: 2,
                                                            raw_currency_unit_price: BigDecimal("450.5"),
                                                            unit: "day", vat_rate: "FR_200" }]))
  end

  # names: updateQuote
  def test_update_sends_only_the_given_attributes
    stub_request(:put, "#{API}/quotes/9").with(body: '{"pdf_invoice_subject":"Audit, phase 2"}')
                                         .to_return(status: 200, body: '{"id":9}')

    assert_equal({ id: 9 }, quotes.update(9, pdf_invoice_subject: "Audit, phase 2"))
  end

  # names: sendByEmailQuote
  def test_send_by_email_to_given_recipients
    stub_request(:post, "#{API}/quotes/9/send_by_email")
      .with(body: '{"recipients":["billing@example.com"]}').to_return(status: 204)

    assert_same true, quotes.send_by_email(9, recipients: ["billing@example.com"])
  end

  def test_send_by_email_to_the_customer_by_default
    stub_request(:post, "#{API}/quotes/9/send_by_email").with(body: "{}").to_return(status: 204)

    assert_same true, quotes.send_by_email(9)
  end

  # Pennylane answers 409 while the PDF is still being generated.
  def test_send_by_email_before_the_pdf_exists_raises_conflict
    stub_request(:post, "#{API}/quotes/9/send_by_email").to_return(status: 409, body: "{}")

    assert_raises(PennylaneClient::ConflictError) { quotes.send_by_email(9) }
  end

  # names: updateStatusQuote
  def test_update_status
    stub_request(:put, "#{API}/quotes/9/update_status").with(body: '{"status":"accepted"}')
                                                       .to_return(status: 200, body: '{"id":9,"status":"accepted"}')

    assert_equal({ id: 9, status: "accepted" }, quotes.update_status(9, status: "accepted"))
  end

  # names: getQuoteInvoiceLines
  def test_invoice_lines_walks_every_page
    stub_request(:get, "#{API}/quotes/9/invoice_lines").with(query: { sort: "-id", limit: "100" })
                                                       .to_return(status: 200, body: page(1, 2))

    assert_equal [1, 2], quotes.invoice_lines(9, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getQuoteInvoiceLineSections
  def test_invoice_line_sections_walks_every_page
    stub_request(:get, "#{API}/quotes/9/invoice_line_sections").with(query: { limit: "100" })
                                                               .to_return(status: 200, body: page(1, 2))

    assert_equal [1, 2], quotes.invoice_line_sections(9).map { _1[:id] }.to_a
  end

  # names: getQuoteAppendices
  def test_appendices_walks_every_page
    stub_request(:get, "#{API}/quotes/9/appendices").with(query: { limit: "10" })
                                                    .to_return(status: 200, body: page(1, 2))

    assert_equal [1, 2], quotes.appendices(9, limit: 10).map { _1[:id] }.to_a
  end

  # names: postQuoteAppendices
  def test_upload_appendix_streams_the_file
    file_part = %(name="file"; filename="terms.pdf"\r\nContent-Type: application/pdf\r\n\r\n%PDF-1.7)
    stub_request(:post, "#{API}/quotes/9/appendices").with do |request|
      request.headers["Content-Type"].start_with?("multipart/form-data; boundary=") && request.body.include?(file_part)
    end.to_return(status: 201, body: '{"id":8}')

    file = PennylaneClient::Upload.new(StringIO.new("%PDF-1.7"), filename: "terms.pdf")

    assert_equal({ id: 8 }, quotes.upload_appendix(9, file))
  end
end
