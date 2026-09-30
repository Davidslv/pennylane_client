# frozen_string_literal: true

require "test_helper"
require "logger"
require "pp"
require "stringio"

# AGENTS.md hard rule 3: the token never appears in logs, inspect,
# exceptions or the on_request event.
class TokenSecrecyTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"
  TOKEN = "pl-secret-token-7f3a9c"

  # max_retry_wait: 0 keeps backoff retries, and their real sleeps, out of
  # the suite; a 429 with retry-after 0 still retries.
  def setup
    @log = StringIO.new
    @events = []
    @client = PennylaneClient.new(token: TOKEN, logger: Logger.new(@log, level: :debug),
                                  on_request: @events.method(:<<), limiters: PennylaneClient::LimiterRegistry.new,
                                  max_retry_wait: 0.0)
  end

  def test_not_in_inspect
    refute_includes @client.inspect, TOKEN
    refute_includes @client.to_s, TOKEN
    refute_includes PP.pp(@client, +""), TOKEN
  end

  def test_not_in_a_resource_inspect
    refute_includes @client.customer_invoices.inspect, TOKEN
    refute_includes PP.pp(@client.customer_invoices, +""), TOKEN
  end

  def test_not_in_log_output_or_events
    stub_answers
    @client.call(:getMe)
    assert_raises(PennylaneClient::NotFoundError) { @client.call(:getJournal, id: 1) }
    assert_raises(PennylaneClient::TimeoutError) { @client.call(:getJournal, id: 2) }

    assert_equal(%i[request request request retry request], @events.map { _1[:type] })
    refute_includes @log.string, TOKEN
    refute_includes @events.inspect, TOKEN
  end

  def test_not_in_error_messages
    [[401, "{}"], [422, '{"error":"x","message":"y"}'], [500, "oops"]].each do |status, body|
      stub_request(:get, "#{API}/me").to_return(status:, body:)
      refute_token_in(assert_raises(PennylaneClient::Error) { @client.call(:getMe) })
    end
    stub_request(:get, "#{API}/me").to_raise(Errno::ECONNREFUSED)
    refute_token_in(assert_raises(PennylaneClient::ConnectionError) { @client.call(:getMe) })
  end

  # Net::HTTP would reject the header with the token in its message.
  def test_a_token_with_a_line_break_is_refused_without_echoing_it
    error = assert_raises(ArgumentError) { PennylaneClient.new(token: "#{TOKEN}\nX-Evil: 1") }

    refute_includes error.message, TOKEN
  end

  private

  # A success, a failure status, and a retried call that never gets an answer.
  def stub_answers
    stub_request(:get, "#{API}/me").to_return(status: 200, body: "{}")
    stub_request(:get, "#{API}/journals/1").to_return(status: 404, body: "{}")
    stub_request(:get, "#{API}/journals/2").to_return(status: 429, headers: { "Retry-After" => "0" }).then.to_timeout
  end

  def refute_token_in(error)
    refute_includes error.message, TOKEN
    refute_includes error.inspect, TOKEN
    refute_includes error.full_message, TOKEN
  end
end
