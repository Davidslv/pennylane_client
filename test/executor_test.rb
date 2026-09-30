# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "date"
require "minitest/mock"
require "pathname"
require "stringio"
require "tmpdir"

module ExecutorHelpers
  BASE = "https://app.pennylane.com"

  def ok(status = 200, body = "{}", headers = {})
    PennylaneClient::Response.new(status:, headers:, body:)
  end

  def executor(*responses)
    @transport = FakeTransport.new(*responses.then { _1.empty? ? [ok] : _1 })
    PennylaneClient::Executor.new(registry: PennylaneClient::Registry.default, transport: @transport,
                                  base_url: BASE)
  end

  def sent = @transport.requests.last
end

class ExecutorTest < Minitest::Test
  include ExecutorHelpers

  def test_fills_path_parameters_and_sends_the_rest_as_the_query
    executor.call(:getCustomerInvoiceMatchedTransactions, { customer_invoice_id: 42, limit: 5, cursor: "abc" })

    assert_equal :get, sent.verb
    assert_equal "#{BASE}/api/external/v2/customer_invoices/42/matched_transactions?limit=5&cursor=abc", sent.url
    assert_nil sent.body
  end

  def test_escapes_path_parameters
    executor.call(:getJournal, { id: "a/b c" })

    assert_equal "#{BASE}/api/external/v2/journals/a%2Fb%20c", sent.url
  end

  def test_sends_filter_and_other_structured_query_values_as_json
    executor.call(:getJournals, { filter: [{ field: "code", operator: "eq", value: "HA" }], sort: "-id" })

    query = URI.decode_www_form(URI(sent.url).query).to_h

    assert_equal '[{"field":"code","operator":"eq","value":"HA"}]', query["filter"]
    assert_equal "-id", query["sort"]
  end

  def test_leaves_out_nil_query_values
    executor.call(:getJournals, { cursor: nil })

    assert_equal "#{BASE}/api/external/v2/journals", sent.url
  end

  def test_sends_the_rest_as_an_encoded_json_body_when_the_operation_takes_one
    executor.call(:putCategoryGroup, { id: 7, label: "Sales", amount: BigDecimal("12.50"), date: Date.new(2026, 1, 2) })

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

  # The token is added by Middleware::Auth; the Executor never holds it.
  def test_asks_for_json_without_the_token
    executor.call(:getMe)
    headers = sent.headers

    refute headers.key?("Authorization")
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

  def test_returns_a_deep_frozen_hash_with_symbol_keys
    result = executor(ok(200, '{"id":1,"lines":[{"label":"Rent"}]}')).call(:getJournal, { id: 1 })

    assert_equal({ id: 1, lines: [{ label: "Rent" }] }, result)
    assert_predicate result, :frozen?
    assert_predicate result[:lines].first[:label], :frozen?
  end

  def test_returns_true_for_an_empty_success_body
    assert(executor(ok(204, "")).call(:markAsPaidCustomerInvoice, { id: 1 }))
  end

  def test_treats_a_nil_body_from_a_custom_transport_as_empty
    assert(executor(PennylaneClient::Response.new(status: 204, headers: {}, body: nil)).call(:getMe))
  end

  def test_raises_the_mapped_error_for_a_failure_status
    error = assert_raises(PennylaneClient::NotFoundError) do
      executor(ok(404, '{"error":"not_found","message":"Journal not found"}')).call(:getJournal, { id: 1 })
    end

    assert_equal "404 not_found: Journal not found", error.message
  end

  def test_raises_when_a_success_body_is_not_json
    error = assert_raises(PennylaneClient::Error) { executor(ok(200, "<html>")).call(:getMe) }

    assert_equal 200, error.status
  end

  # Net::HTTP does not follow redirects, so a 3xx reaches the Executor.
  # An empty 302 must not read as the success of a write.
  def test_raises_for_an_empty_redirect
    error = assert_raises(PennylaneClient::Error) do
      executor(ok(302, "", { "location" => "https://example.com" })).call(:markAsPaidCustomerInvoice, { id: 1 })
    end

    assert_equal 302, error.status
  end

  def test_raises_for_not_modified
    error = assert_raises(PennylaneClient::Error) { executor(ok(304, "")).call(:getMe) }

    assert_equal 304, error.status
  end

  def test_names_the_operation_on_the_request
    executor.call(:getMe)

    assert_equal :getMe, sent.operation_id
    assert_equal :default, sent.retry_policy
  end

  def test_passes_the_retry_policy_on_the_request
    executor(ok(201)).call(:postJournals, { code: "HA" }, nil, retry_policy: :always)

    assert_equal :always, sent.retry_policy
  end
end

# Path parameters that would change which Operation the path names.
class ExecutorPathTest < Minitest::Test
  include ExecutorHelpers

  # A nil or empty id would leave an empty segment, so GET /customer_invoices/
  # would answer with the list as if it were one invoice.
  def test_refuses_a_nil_or_empty_path_parameter_without_sending_anything
    [nil, ""].each do |id|
      executor = executor()
      error = assert_raises(ArgumentError) { executor.call(:getCustomerInvoice, { id: }) }

      assert_equal "path parameter :id for :getCustomerInvoice is empty", error.message
      assert_empty @transport.requests
    end
  end

  # "." and ".." would be dot segments: /customer_invoices/5/matched_transactions/..
  # normalises to /customer_invoices/5, another Operation on the same verb.
  def test_refuses_a_dot_segment_path_parameter_without_sending_anything
    [".", ".."].each do |id|
      executor = executor()
      error = assert_raises(ArgumentError) do
        executor.call(:deleteCustomerInvoiceMatchedTransactions, { customer_invoice_id: 5, id: })
      end

      assert_equal "path parameter :id for :deleteCustomerInvoiceMatchedTransactions cannot be #{id.inspect}",
                   error.message
      assert_empty @transport.requests
    end
  end

  def test_still_sends_dots_inside_a_path_parameter
    executor.call(:getJournal, { id: "a.b..c" })

    assert_equal "#{BASE}/api/external/v2/journals/a.b..c", sent.url
  end
end

class ExecutorMultipartTest < Minitest::Test
  include ExecutorHelpers

  def test_sends_a_multipart_operation_as_a_streamed_form
    executor.call(:postCustomerInvoiceAppendices, { customer_invoice_id: 42, file: StringIO.new("%PDF") })

    assert_equal "#{BASE}/api/external/v2/customer_invoices/42/appendices", sent.url
    assert_instance_of PennylaneClient::Multipart, sent.body
    assert_includes sent.body.read, "%PDF"
  end

  def test_sends_the_form_content_type_and_length
    executor.call(:postFileAttachments, { file: StringIO.new("%PDF") })
    form = sent.body

    assert_equal [form.content_type, form.size.to_s], sent.headers.values_at("Content-Type", "Content-Length")
  end

  def test_refuses_a_positional_body_for_a_multipart_operation
    assert_raises(ArgumentError) { executor.call(:postFileAttachments, {}, "x") }
  end

  def test_closes_the_files_it_opened_once_the_call_is_over
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("receipt.pdf").tap { _1.write("%PDF") }
      opened = files_opened { reading_executor.call(:postFileAttachments, { file: path }) }

      assert_equal 1, opened.size
      assert_predicate opened.first, :closed?
    end
  end

  private

  # Reads the body, as a real Transport would, which opens the file.
  def reading_executor
    PennylaneClient::Executor.new(registry: PennylaneClient::Registry.default,
                                  transport: ->(request) { request.body.read && ok(201) }, base_url: BASE)
  end

  def files_opened(&)
    opened = []
    original = File.method(:new)
    File.stub(:new, ->(*args) { original.call(*args).tap { opened << _1 } }, &)
    opened
  end
end
