# frozen_string_literal: true

require "test_helper"

# client.call end to end: Client, Registry, Executor and NetHttpTransport,
# with WebMock standing in for Pennylane.
class ClientTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok")

  def test_new_returns_a_client
    assert_instance_of PennylaneClient::Client, client
    assert_instance_of PennylaneClient::Client, PennylaneClient::Client.new(token: "tok")
  end

  def test_refuses_a_missing_token
    assert_raises(ArgumentError) { PennylaneClient.new(token: "") }
    assert_raises(ArgumentError) { PennylaneClient.new(token: nil) }
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

    assert client.call(:markAsPaidCustomerInvoice, id: 42)
  end

  def test_delete_with_a_body
    lines = [{ id: 3455 }]
    stub_request(:delete, "#{API}/ledger_entry_lines/lettering")
      .with(body: { unbalanced_lettering_strategy: "none", ledger_entry_lines: lines }.to_json)
      .to_return(status: 204)

    assert client.call(:deleteLedgerEntryLinesUnletter, unbalanced_lettering_strategy: "none",
                                                        ledger_entry_lines: lines)
  end

  def test_a_failure_status_raises_its_error
    stub_request(:get, "#{API}/me").to_return(status: 401, body: '{"error":"unauthorized","message":"Bad token"}')

    assert_raises(PennylaneClient::AuthenticationError) { client.call(:getMe) }
  end

  def test_an_unknown_operation_raises
    assert_raises(PennylaneClient::UnknownOperationError) { client.call(:getNothing) }
  end

  def test_base_url_and_transport_can_be_injected
    transport = ->(request) { PennylaneClient::Response.new(status: 200, headers: {}, body: %({"url":"#{request.url}"})) }
    custom = PennylaneClient.new(token: "tok", base_url: "http://localhost:9292", transport:)

    assert_equal({ url: "http://localhost:9292/api/external/v2/me" }, custom.call(:getMe))
  end
end
