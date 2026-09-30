# frozen_string_literal: true

require "test_helper"

# GoCardless mandates: `client.gocardless_mandates`. Each stub is the
# method and path from the operation's reference page.
class GocardlessMandatesTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def mandates = client.gocardless_mandates

  def test_is_one_resource_per_client
    assert_same client.gocardless_mandates, client.gocardless_mandates
    refute_includes client.gocardless_mandates.inspect, "tok"
  end

  # names: getGocardlessMandates
  def test_list_walks_every_page_resending_the_filter
    by_reference = [{ field: "external_reference", operator: "eq", value: "MD-1" }]
    query = { filter: JSON.generate(by_reference), sort: "-id", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    last = JSON.generate({ items: [{ id: 2 }], has_more: false, next_cursor: nil })
    stub_request(:get, "#{API}/gocardless_mandates").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/gocardless_mandates").with(query: query.merge(cursor: "c2"))
                                                    .to_return(status: 200, body: last)

    assert_equal [1, 2], mandates.list(filter: by_reference, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getGocardlessMandate
  def test_find
    stub_request(:get, "#{API}/gocardless_mandates/5").to_return(status: 200, body: '{"id":5,"status":"active"}')

    assert_equal({ id: 5, status: "active" }, mandates.find(5))
  end

  # names: postGocardlessMandateMailRequests
  def test_send_request_emails_the_customer_and_returns_true
    stub_request(:post, "#{API}/gocardless_mandates/mail_requests")
      .with(body: '{"customer_id":7,"email":{"recipients":["billing@acme.example"],"subject":"Direct debit"}}')
      .to_return(status: 204)

    assert_same true, mandates.send_request(customer_id: 7, email: { recipients: ["billing@acme.example"],
                                                                     subject: "Direct debit" })
  end

  def test_send_request_without_recipients_raises_before_any_request
    assert_raises(ArgumentError) { mandates.send_request(customer_id: 7) }
    assert_not_requested :any, /gocardless_mandates/
  end

  # names: postGocardlessMandateAssociations
  def test_associate_links_the_mandate_to_a_customer_and_returns_true
    stub_request(:post, "#{API}/gocardless_mandates/5/associations").with(body: '{"customer_id":7}')
                                                                    .to_return(status: 200, body: "")

    assert_same true, mandates.associate(5, customer_id: 7)
  end

  # names: postGocardlessMandateCancellations
  def test_cancel_returns_true
    stub_request(:post, "#{API}/gocardless_mandates/5/cancellations").with(body: nil).to_return(status: 204)

    assert_same true, mandates.cancel(5)
  end

  # Only a pending_submission, submitted or active mandate can be cancelled.
  def test_cancel_of_a_mandate_past_cancelling_raises_validation_error
    stub_request(:post, "#{API}/gocardless_mandates/5/cancellations")
      .to_return(status: 422, body: '{"error":"Mandate cannot be cancelled"}')

    assert_raises(PennylaneClient::ValidationError) { mandates.cancel(5) }
  end
end
