# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"

class InstrumentTest < Minitest::Test
  def setup
    @events = []
    @log = StringIO.new
  end

  def instrument(*responses)
    instrumentation = PennylaneClient::Instrumentation.new(logger: Logger.new(@log), on_request: @events.method(:<<))
    PennylaneClient::Middleware::Instrument.new(FakeTransport.new(*responses), instrumentation)
  end

  def request(verb = :get, path = "/api/external/v2/me", operation_id = :getMe)
    PennylaneClient::Request.new(verb:, url: "https://app.pennylane.com#{path}?limit=5", headers: {}, body: nil,
                                 operation_id:)
  end

  def test_emits_an_event_for_every_request
    response = PennylaneClient::Response.new(status: 201, headers: {}, body: "{}")
    instrument(response).call(request(:post, "/api/external/v2/journals", :postJournals))

    event = @events.fetch(0)

    assert_equal({ type: :request, operation_id: :postJournals, method: "POST", path: "/api/external/v2/journals",
                   status: 201, error: nil }, event.except(:duration))
    assert_kind_of Float, event[:duration]
    assert_predicate event, :frozen?
  end

  def test_emits_an_event_and_logs_when_no_response_arrives
    failing = instrument(PennylaneClient::TimeoutError.new("Net::ReadTimeout"))

    assert_raises(PennylaneClient::TimeoutError) { failing.call(request) }
    assert_equal "PennylaneClient::TimeoutError", @events.fetch(0)[:error]
    assert_nil @events.fetch(0)[:status]
    assert_includes @log.string, "getMe GET /api/external/v2/me failed: PennylaneClient::TimeoutError"
  end

  def test_logs_each_request
    instrument(PennylaneClient::Response.new(status: 200, headers: {}, body: "{}")).call(request)

    assert_match %r{pennylane_client getMe GET /api/external/v2/me -> 200 \(\d+\.\d ms\)}, @log.string
  end
end
