# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class NetHttpTransportTest < Minitest::Test
  BASE = "https://app.pennylane.com/api/external/v2"

  def transport = @transport ||= PennylaneClient::NetHttpTransport.new

  def request(verb: :get, url: "#{BASE}/me", headers: {}, body: nil)
    PennylaneClient::Request.new(verb:, url:, headers:, body:)
  end

  def test_returns_the_status_lower_case_headers_and_body
    stub_request(:get, "#{BASE}/me").to_return(status: 200, body: '{"id":1}',
                                               headers: { "Ratelimit-Remaining" => "24" })

    response = transport.call(request)

    assert_equal 200, response.status
    assert_equal "24", response.headers["ratelimit-remaining"]
    assert_equal '{"id":1}', response.body
  end

  def test_an_empty_body_is_an_empty_string
    stub_request(:put, "#{BASE}/customer_invoices/1/mark_as_paid").to_return(status: 204)

    assert_equal "", transport.call(request(verb: :put, url: "#{BASE}/customer_invoices/1/mark_as_paid")).body
  end

  def test_sends_the_headers_and_a_body_even_on_delete
    stub_request(:delete, "#{BASE}/ledger_entry_lines/lettering")
      .with(body: '{"a":1}', headers: { "Content-Type" => "application/json", "X-Test" => "yes" })
      .to_return(status: 204)

    transport.call(request(verb: :delete, url: "#{BASE}/ledger_entry_lines/lettering",
                           headers: { "Content-Type" => "application/json", "X-Test" => "yes" }, body: '{"a":1}'))
  end

  def test_keeps_one_connection_per_thread
    stub_request(:get, "#{BASE}/me").to_return(status: 200)
    opened = count_connections do
      2.times { transport.call(request) }
      Thread.new { transport.call(request) }.join
    end

    assert_equal 2, opened
  end

  def test_uses_the_documented_timeouts_by_default
    http = transport.send(:connection, URI(BASE))

    assert_equal [5, 30, 30], [http.open_timeout, http.read_timeout, http.write_timeout]
    assert_predicate http, :use_ssl?
  end

  def test_timeouts_are_configurable
    http = PennylaneClient::NetHttpTransport.new(open_timeout: 1, read_timeout: 2, write_timeout: 3)
                                            .send(:connection, URI(BASE))

    assert_equal [1, 2, 3], [http.open_timeout, http.read_timeout, http.write_timeout]
  end

  # Net::HTTP retries idempotent verbs once by default. PUT and DELETE have
  # side effects at Pennylane, so the transport never retries (D5).
  def test_never_lets_net_http_retry
    assert_equal 0, transport.send(:connection, URI(BASE)).max_retries
  end

  def test_a_timeout_becomes_a_timeout_error
    stub_request(:get, "#{BASE}/me").to_timeout

    assert_raises(PennylaneClient::TimeoutError) { transport.call(request) }
  end

  def test_a_refused_connection_becomes_a_connection_error
    stub_request(:get, "#{BASE}/me").to_raise(Errno::ECONNREFUSED)

    assert_raises(PennylaneClient::ConnectionError) { transport.call(request) }
  end

  def test_drops_the_connection_after_a_failure
    stub_request(:get, "#{BASE}/me").to_raise(Errno::ECONNRESET).then.to_return(status: 200)
    opened = count_connections do
      assert_raises(PennylaneClient::ConnectionError) { transport.call(request) }
      transport.call(request)
    end

    assert_equal 2, opened
  end

  private

  def count_connections(&)
    count = 0
    original = Net::HTTP.method(:new)
    Net::HTTP.stub(:new, ->(*args) { count += 1; original.call(*args) }, &) # rubocop:disable Style/Semicolon
    count
  end
end
