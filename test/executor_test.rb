# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "date"
require "logger"
require "stringio"

# Records each Request and answers with a canned Response.
class FakeTransport
  attr_reader :requests

  def initialize(*responses)
    @responses = responses
    @requests = []
  end

  def call(request)
    @requests << request
    response = @responses.shift
    raise response if response.is_a?(Exception)

    response
  end
end

module ExecutorHelpers
  BASE = "https://app.pennylane.com"

  def ok(status = 200, body = "{}", headers = {})
    PennylaneClient::Response.new(status:, headers:, body:)
  end

  def executor(*responses, logger: nil, on_request: nil)
    @transport = FakeTransport.new(*responses.then { _1.empty? ? [ok] : _1 })
    PennylaneClient::Executor.new(registry: PennylaneClient::Registry.default, transport: @transport,
                                  token: "tok", base_url: BASE,
                                  instrumentation: PennylaneClient::Instrumentation.new(logger:, on_request:))
  end

  def sent = @transport.requests.last
end

class ExecutorTest < Minitest::Test
  include ExecutorHelpers

  def test_fills_path_parameters_and_sends_the_rest_as_the_query
    executor.call(:getCustomerInvoiceMatchedTransactions, customer_invoice_id: 42, limit: 5, cursor: "abc")

    assert_equal :get, sent.verb
    assert_equal "#{BASE}/api/external/v2/customer_invoices/42/matched_transactions?limit=5&cursor=abc", sent.url
    assert_nil sent.body
  end

  def test_escapes_path_parameters
    executor.call(:getJournal, id: "a/b c")

    assert_equal "#{BASE}/api/external/v2/journals/a%2Fb%20c", sent.url
  end

  def test_sends_filter_and_other_structured_query_values_as_json
    executor.call(:getJournals, filter: [{ field: "code", operator: "eq", value: "HA" }], sort: "-id")

    query = URI.decode_www_form(URI(sent.url).query).to_h

    assert_equal '[{"field":"code","operator":"eq","value":"HA"}]', query["filter"]
    assert_equal "-id", query["sort"]
  end

  def test_leaves_out_nil_query_values
    executor.call(:getJournals, cursor: nil)

    assert_equal "#{BASE}/api/external/v2/journals", sent.url
  end

  def test_sends_the_rest_as_an_encoded_json_body_when_the_operation_takes_one
    executor.call(:putCategoryGroup, id: 7, label: "Sales", amount: BigDecimal("12.50"), date: Date.new(2026, 1, 2))

    assert_equal [:put, "#{BASE}/api/external/v2/category_groups/7"], [sent.verb, sent.url]
    assert_equal({ "label" => "Sales", "amount" => "12.5", "date" => "2026-01-02" }, JSON.parse(sent.body))
    assert_equal "application/json", sent.headers["Content-Type"]
  end

  # putCustomerCategories and five others take a JSON array, which keyword
  # params cannot build.
  def test_sends_an_explicit_body_as_is
    executor.call(:putCustomerCategories, { customer_id: 9 }, [{ id: 1, weight: BigDecimal("0.5") }])

    assert_equal "#{BASE}/api/external/v2/customers/9/categories", sent.url
    assert_equal '[{"id":1,"weight":"0.5"}]', sent.body
  end

  def test_refuses_extra_params_next_to_an_explicit_body
    error = assert_raises(ArgumentError) do
      executor.call(:putCustomerCategories, { customer_id: 9, weight: 1 }, [])
    end

    assert_equal "unexpected parameters [:weight] for :putCustomerCategories with an explicit body", error.message
  end

  def test_refuses_an_explicit_body_for_an_operation_without_one
    assert_raises(ArgumentError) { executor.call(:getMe, {}, []) }
  end

  def test_sends_the_token_and_asks_for_json
    executor.call(:getMe)
    headers = sent.headers

    assert_equal "Bearer tok", headers["Authorization"]
    assert_equal "application/json", headers["Accept"]
    assert_match %r{\Apennylane_client/#{PennylaneClient::VERSION} }o, headers["User-Agent"]
    refute headers.key?("Content-Type")
  end

  def test_raises_on_a_missing_path_parameter
    error = assert_raises(ArgumentError) { executor.call(:getJournal) }

    assert_equal "missing path parameter :id for :getJournal", error.message
  end

  def test_raises_on_an_unknown_operation_without_sending_anything
    assert_raises(PennylaneClient::UnknownOperationError) { executor.call(:nope) }
    assert_empty @transport.requests
  end

  def test_refuses_multipart_operations_until_uploads_land
    assert_raises(NotImplementedError) { executor.call(:postFileAttachments, file: "x") }
  end

  def test_returns_a_deep_frozen_hash_with_symbol_keys
    result = executor(ok(200, '{"id":1,"lines":[{"label":"Rent"}]}')).call(:getJournal, id: 1)

    assert_equal({ id: 1, lines: [{ label: "Rent" }] }, result)
    assert_predicate result, :frozen?
    assert_predicate result[:lines].first[:label], :frozen?
  end

  def test_returns_true_for_an_empty_success_body
    assert(executor(ok(204, "")).call(:markAsPaidCustomerInvoice, id: 1))
  end

  def test_treats_a_nil_body_from_a_custom_transport_as_empty
    assert(executor(PennylaneClient::Response.new(status: 204, headers: {}, body: nil)).call(:getMe))
  end

  def test_raises_the_mapped_error_for_a_failure_status
    error = assert_raises(PennylaneClient::NotFoundError) do
      executor(ok(404, '{"error":"not_found","message":"Journal not found"}')).call(:getJournal, id: 1)
    end

    assert_equal "404 not_found: Journal not found", error.message
  end

  def test_raises_when_a_success_body_is_not_json
    error = assert_raises(PennylaneClient::Error) { executor(ok(200, "<html>")).call(:getMe) }

    assert_equal 200, error.status
  end
end

class ExecutorEventsTest < Minitest::Test
  include ExecutorHelpers

  def test_emits_an_event_for_every_request
    events = []
    executor(ok(201, "{}"), on_request: events.method(:<<)).call(:postJournals, code: "HA")

    event = events.fetch(0)

    assert_equal({ operation_id: :postJournals, method: "POST", path: "/api/external/v2/journals", status: 201,
                   error: nil }, event.except(:duration))
    assert_kind_of Float, event[:duration]
    assert_predicate event, :frozen?
  end

  def test_emits_an_event_and_logs_when_no_response_arrives
    events = []
    log = StringIO.new
    failing = executor(PennylaneClient::TimeoutError.new("Net::ReadTimeout"), on_request: events.method(:<<),
                                                                              logger: Logger.new(log))

    assert_raises(PennylaneClient::TimeoutError) { failing.call(:getMe) }
    assert_equal "PennylaneClient::TimeoutError", events.fetch(0)[:error]
    assert_nil events.fetch(0)[:status]
    assert_includes log.string, "getMe GET /api/external/v2/me failed: PennylaneClient::TimeoutError"
  end

  def test_logs_each_request
    log = StringIO.new
    executor(ok, logger: Logger.new(log)).call(:getMe)

    assert_match %r{pennylane_client getMe GET /api/external/v2/me -> 200 \(\d+\.\d ms\)}, log.string
  end
end
