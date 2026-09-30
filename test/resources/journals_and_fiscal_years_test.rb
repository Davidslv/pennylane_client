# frozen_string_literal: true

require "test_helper"

# Journals, fiscal years and file attachments: `client.journals`,
# `client.fiscal_years`, `client.file_attachments`. Each stub is the method
# and path from the operation's reference page.
class JournalsAndFiscalYearsTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    %i[journals fiscal_years file_attachments].each do |name|
      assert_same client.public_send(name), client.public_send(name)
      refute_includes client.public_send(name).inspect, "tok"
    end
  end

  # names: getJournals
  def test_journals_list_walks_every_page_resending_the_filter
    bank = [{ field: "type", operator: "eq", value: "bank" }]
    query = { filter: JSON.generate(bank), sort: "-id", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/journals").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/journals").with(query: query.merge(cursor: "c2")).to_return(status: 200, body: page(2))

    assert_equal [1, 2], client.journals.list(filter: bank, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getJournal
  def test_journals_find
    stub_request(:get, "#{API}/journals/4").to_return(status: 200, body: '{"id":4,"code":"HA"}')

    assert_equal({ id: 4, code: "HA" }, client.journals.find(4))
  end

  # names: postJournals
  def test_journals_create
    stub_request(:post, "#{API}/journals").with(body: '{"code":"BQ2","label":"Second bank"}')
                                          .to_return(status: 201, body: '{"id":5,"code":"BQ2"}')

    assert_equal({ id: 5, code: "BQ2" }, client.journals.create(code: "BQ2", label: "Second bank"))
  end

  # names: company-fiscal-years
  def test_fiscal_years_list_walks_every_page
    stub_request(:get, "#{API}/fiscal_years").with(query: { sort: "start", limit: "100" })
                                             .to_return(status: 200, body: page(1, 2))

    assert_equal [1, 2], client.fiscal_years.list(sort: "start").map { _1[:id] }.to_a
  end

  # names: postFileAttachments
  def test_file_attachments_upload_streams_the_file_with_its_filename
    file_part = %(name="file"; filename="receipt.pdf"\r\nContent-Type: application/pdf\r\n\r\n%PDF-1.7)
    name_part = %(name="filename"\r\n\r\nMarch receipt.pdf)
    stub_request(:post, "#{API}/file_attachments").with do |request|
      request.headers["Content-Type"].start_with?("multipart/form-data; boundary=") &&
        request.body.include?(file_part) && request.body.include?(name_part)
    end.to_return(status: 201, body: '{"id":8}')

    file = PennylaneClient::Upload.new(StringIO.new("%PDF-1.7"), filename: "receipt.pdf")

    assert_equal({ id: 8 }, client.file_attachments.upload(file, filename: "March receipt.pdf"))
  end
end
