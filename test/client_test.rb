# frozen_string_literal: true

require "test_helper"

# client.call end to end: Client, Registry, Executor and NetHttpTransport,
# with WebMock standing in for Pennylane.
class ClientTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  # A fresh LimiterRegistry per test, so the suite never waits on the
  # process-wide bucket.
  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)

  def test_new_returns_a_client
    assert_instance_of PennylaneClient::Client, client
    assert_instance_of PennylaneClient::Client, PennylaneClient::Client.new(token: "tok")
  end

  def test_refuses_a_missing_token
    assert_raises(ArgumentError) { PennylaneClient.new(token: "") }
    assert_raises(ArgumentError) { PennylaneClient.new(token: nil) }
  end

  def test_takes_a_token_provider
    stub_request(:get, "#{API}/me").with(headers: { "Authorization" => "Bearer fresh" }).to_return(status: 200)

    assert PennylaneClient.new(token: -> { "fresh" }, limiters: PennylaneClient::LimiterRegistry.new).call(:getMe)
  end

  def test_get
    stub_request(:get, "#{API}/journals/42").with(headers: { "Authorization" => "Bearer tok" })
                                            .to_return(status: 200, body: '{"id":42,"code":"HA"}')

    assert_equal({ id: 42, code: "HA" }, client.call(:getJournal, id: 42))
  end

  def test_post_with_a_json_body
    stub_request(:post, "#{API}/journals")
      .with(body: { code: "HA", label: "Achats" }.to_json, headers: { "Content-Type" => "application/json" })
      .to_return(status: 201, body: '{"id":7}')

    assert_equal({ id: 7 }, client.call(:postJournals, code: "HA", label: "Achats"))
  end

  def test_put_returning_no_content
    stub_request(:put, "#{API}/customer_invoices/42/mark_as_paid").to_return(status: 204)

    assert_same true, client.call(:markAsPaidCustomerInvoice, id: 42)
  end

  def test_delete_with_a_body
    lines = [{ id: 3455 }]
    stub_request(:delete, "#{API}/ledger_entry_lines/lettering")
      .with(body: { unbalanced_lettering_strategy: "none", ledger_entry_lines: lines }.to_json)
      .to_return(status: 204)

    assert_same true, client.call(:deleteLedgerEntryLinesUnletter, unbalanced_lettering_strategy: "none",
                                                                   ledger_entry_lines: lines)
  end

  def test_an_array_body_goes_as_the_second_argument
    stub_request(:put, "#{API}/customers/9/categories").with(body: '[{"id":1,"weight":"1"}]')
                                                       .to_return(status: 200, body: "[]")

    assert_equal [], client.call(:putCustomerCategories, [{ id: 1, weight: "1" }], customer_id: 9)
  end

  def test_a_failure_status_raises_its_error
    stub_request(:get, "#{API}/me").to_return(status: 401, body: '{"error":"unauthorized","message":"Bad token"}')

    assert_raises(PennylaneClient::AuthenticationError) { client.call(:getMe) }
  end

  def test_an_unknown_operation_raises
    assert_raises(PennylaneClient::UnknownOperationError) { client.call(:getNothing) }
  end

  def test_retries_a_post_when_rate_limited
    stub_request(:post, "#{API}/journals").to_return({ status: 429, headers: { "Retry-After" => "0" } },
                                                     { status: 201, body: '{"id":7}' })

    assert_equal({ id: 7 }, client.call(:postJournals, code: "HA"))
  end

  def test_raises_rate_limit_error_when_retries_run_out
    stub_request(:get, "#{API}/me").to_return(status: 429, headers: { "Retry-After" => "0" })

    error = assert_raises(PennylaneClient::RateLimitError) { client.call(:getMe) }

    assert_in_delta 0.0, error.retry_after
    assert_requested :get, "#{API}/me", times: 3
  end

  def test_never_retries_a_post_after_a_5xx
    stub_request(:post, "#{API}/journals").to_return(status: 503)

    assert_raises(PennylaneClient::ServerError) { client.call(:postJournals, code: "HA") }
    assert_requested :post, "#{API}/journals", times: 1
  end

  def test_retry_always_is_not_sent_to_pennylane
    stub_request(:post, "#{API}/journals").with(body: '{"code":"HA"}').to_return(status: 201, body: "{}")

    assert_equal({}, client.call(:postJournals, code: "HA", retry: :always))
  end

  def test_refuses_an_unknown_retry_policy
    error = assert_raises(ArgumentError) { client.call(:getMe, retry: true) }

    assert_equal "retry must be :always, got true", error.message
  end

  def test_rate_limit_headers_reach_the_injected_limiter
    stub_request(:get, "#{API}/me").to_return(status: 200, headers: { "RateLimit-Remaining" => "7" })
    limiter = RecordingLimiter.new

    PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new { limiter }).call(:getMe)

    assert_equal [{ remaining: 7, reset_at: nil }], limiter.updates
  end

  # A limiter that never waits and keeps every header update.
  class RecordingLimiter
    attr_reader :updates

    def initialize = @updates = []
    def acquire = 0.0
    def update(**headers) = @updates << headers
  end

  def test_base_url_and_transport_can_be_injected
    transport = ->(request) { PennylaneClient::Response.new(status: 200, headers: {}, body: %({"url":"#{request.url}"})) }
    custom = PennylaneClient.new(token: "tok", base_url: "http://localhost:9292", transport:)

    assert_equal({ url: "http://localhost:9292/api/external/v2/me" }, custom.call(:getMe))
  end
end

# Uploads end to end, with WebMock as Pennylane.
class ClientUploadTest < Minitest::Test
  API = ClientTest::API

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)

  def test_uploads_a_file_with_its_filename
    stub_request(:post, "#{API}/file_attachments")
      .with { _1.body.include?(%(name="file"; filename="receipt.pdf")) && _1.body.include?("%PDF-1.7") }
      .to_return(status: 201, body: '{"id":5}')

    upload = PennylaneClient::Upload.new(StringIO.new("%PDF-1.7"), filename: "receipt.pdf")

    assert_equal({ id: 5 }, client.call(:postFileAttachments, file: upload))
  end

  # A 429 means Pennylane did not run the upload, so Retry sends it again,
  # and the file must go again from its first byte.
  def test_a_retried_upload_sends_the_whole_file_again
    bodies = []
    stub_request(:post, "#{API}/file_attachments").with { bodies << _1.body }
                                                  .to_return({ status: 429, headers: { "Retry-After" => "0" } },
                                                             { status: 201, body: '{"id":5}' })

    client.call(:postFileAttachments, file: StringIO.new("%PDF-1.7"))

    assert_equal 2, bodies.size
    assert_equal bodies.first, bodies.last
    assert_includes bodies.last, "%PDF-1.7"
  end
end

# client.paginate and client.pages end to end, with WebMock as Pennylane.
class ClientPaginationTest < Minitest::Test
  API = ClientTest::API
  DRAFTS = [{ field: "status", operator: "eq", value: "draft" }].freeze

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)

  # Matches only a request carrying the filter, the sort and the page size.
  def stub_page(cursor, ids, next_cursor)
    query = { filter: JSON.generate(DRAFTS), sort: "-id", limit: "100", cursor: }.compact
    body = JSON.generate({ items: ids.map { { id: _1 } }, has_more: !next_cursor.nil?, next_cursor: })
    stub_request(:get, "#{API}/customer_invoices").with(query:).to_return(status: 200, body:)
  end

  def test_paginate_follows_three_pages_sending_the_filter_on_each
    pages = [stub_page(nil, [1, 2], "c2"), stub_page("c2", [3], "c3"), stub_page("c3", [4], nil)]

    items = client.paginate(:getCustomerInvoices, filter: DRAFTS, sort: "-id")

    assert_equal [1, 2, 3, 4], items.map { _1[:id] }.to_a
    pages.each { assert_requested(_1, times: 1) }
  end

  # A GET is retried already, and `retry` must never reach Pennylane.
  def test_paginate_refuses_a_retry_policy
    assert_raises(ArgumentError) { client.paginate(:getCustomerInvoices, retry: :always) }
  end

  def test_pages_gives_each_page
    stub_page(nil, [1], "c2")
    stub_page("c2", [2], nil)

    pages = client.pages(:getCustomerInvoices, filter: DRAFTS, sort: "-id").to_a

    assert_equal([[{ id: 1 }], [{ id: 2 }]], pages.map { _1[:items] })
  end
end
