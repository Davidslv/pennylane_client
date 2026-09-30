# frozen_string_literal: true

require "test_helper"

# Builds a Paginator over a FakeTransport and reads back what it sent.
module PaginatorTestHelpers
  def ok(status, body) = PennylaneClient::Response.new(status:, headers: {}, body:)

  def executor(*responses)
    @transport = FakeTransport.new(*responses)
    PennylaneClient::Executor.new(registry: PennylaneClient::Registry.default, transport: @transport,
                                  base_url: "https://app.pennylane.com")
  end

  def page(ids, next_cursor: nil, has_more: !next_cursor.nil?)
    ok(200, JSON.generate({ items: ids.map { { id: _1 } }, has_more:, next_cursor: }))
  end

  def paginator(operation_id, params = {}, responses: [page([1])])
    executor = executor(*responses)
    PennylaneClient::Paginator.new(executor:, operation: PennylaneClient::Registry.default.fetch(operation_id),
                                   params:)
  end

  def queries = @transport.requests.map { URI.decode_www_form(URI(_1.url).query.to_s).to_h }
end

class PaginatorTest < Minitest::Test
  include PaginatorTestHelpers

  DRAFTS = [{ field: "status", operator: "eq", value: "draft" }].freeze

  def test_follows_next_cursor_and_resends_filter_and_sort_on_every_page
    three = [page([1, 2], next_cursor: "c2"), page([3], next_cursor: "c3"), page([4])]
    items = paginator(:getCustomerInvoices, { filter: DRAFTS, sort: "-id" }, responses: three).items

    assert_equal [1, 2, 3, 4], items.map { _1[:id] }.to_a
    sent = [nil, "c2", "c3"].map { { "filter" => JSON.generate(DRAFTS), "sort" => "-id", "cursor" => _1 }.compact }

    assert_equal(sent, queries.map { _1.slice("filter", "sort", "cursor") })
  end

  def test_stops_when_next_cursor_is_null
    items = paginator(:getCustomerInvoices, responses: [page([1], next_cursor: "c2"), page([2]), page([3])]).items

    assert_equal [1, 2], items.map { _1[:id] }.to_a
    assert_equal 2, @transport.requests.size
  end

  def test_stops_when_has_more_is_false_even_with_a_cursor
    items = paginator(:getCustomerInvoices, responses: [page([1], next_cursor: "c2", has_more: false), page([2])])
            .items

    assert_equal [1], items.map { _1[:id] }.to_a
  end

  def test_asks_for_the_largest_page_the_operation_allows
    paginator(:getCustomerInvoices).items.to_a

    assert_equal "100", queries.first["limit"]

    paginator(:getLedgerAccounts).items.to_a

    assert_equal "1000", queries.first["limit"]
  end

  def test_keeps_a_smaller_limit_the_caller_asked_for
    paginator(:getCustomerInvoices, { limit: 20 }).items.to_a

    assert_equal "20", queries.first["limit"]
  end

  def test_refuses_a_limit_above_the_operation_maximum
    error = assert_raises(ArgumentError) { paginator(:getCustomerInvoices, { limit: 101 }) }
    assert_match(/getCustomerInvoices.*100/, error.message)
  end

  def test_is_lazy
    items = paginator(:getCustomerInvoices, responses: [page([1, 2], next_cursor: "c2"), page([3])]).items

    assert_instance_of Enumerator::Lazy, items
    assert_empty @transport.requests
    assert_equal([1], items.first(1).map { _1[:id] })
    assert_equal 1, @transport.requests.size
  end

  def test_gives_the_pages_themselves
    pages = paginator(:getCustomerInvoices, responses: [page([1, 2], next_cursor: "c2"), page([3])]).pages

    assert_instance_of Enumerator::Lazy, pages
    assert_equal [[true, "c2"], [false, nil]], pages.map { [_1[:has_more], _1[:next_cursor]] }.to_a
  end

  def test_fills_path_parameters_on_every_page
    paginator(:getCustomerInvoiceMatchedTransactions, { customer_invoice_id: 42 },
              responses: [page([1], next_cursor: "c2"), page([2])]).items.to_a

    assert(@transport.requests.all? { URI(_1.url).path.end_with?("/customer_invoices/42/matched_transactions") })
  end

  # Every changelog operation answers 400 to `start_date` next to a
  # `cursor`, so it goes with the first request only.
  def test_sends_start_date_on_the_first_page_only
    paginator(:getCustomerChanges, { start_date: "2026-09-29T10:00:00Z" },
              responses: [page([1], next_cursor: "c2"), page([2], next_cursor: "c3"), page([3])]).items.to_a

    assert_equal([["2026-09-29T10:00:00Z", nil], [nil, "c2"], [nil, "c3"]],
                 queries.map { _1.values_at("start_date", "cursor") })
  end

  def test_refuses_start_date_next_to_a_cursor
    error = assert_raises(ArgumentError) do
      paginator(:getCustomerChanges, { start_date: "2026-09-29T10:00:00Z", cursor: "c2" })
    end
    assert_match(/start_date/, error.message)
  end

  # Keys given as Strings follow the same rules as Symbols.
  def test_string_keys_follow_the_start_date_rules
    assert_raises(ArgumentError) { paginator(:getCustomerChanges, { "start_date" => "x", "cursor" => "c2" }) }
    paginator(:getCustomerChanges, { "start_date" => "x" }, responses: [page([1], next_cursor: "c2"), page([2])])
      .items.to_a

    assert_equal([["x", nil], [nil, "c2"]], queries.map { _1.values_at("start_date", "cursor") })
  end

  # getPaRegistrations answers with items, has_more and next_cursor but takes
  # no cursor, so it is one page, sent without cursor or limit.
  def test_reads_a_list_that_takes_no_cursor_as_one_page
    items = paginator(:getPaRegistrations, responses: [page([1, 2]), page([3])]).items

    assert_equal [1, 2], items.map { _1[:id] }.to_a
    assert_equal [{}], queries
  end

  # With no cursor to send, a second page cannot be asked for. Returning
  # the first would drop the rest without a word, so the walk raises.
  def test_raises_when_a_list_that_takes_no_cursor_has_more
    [page([1, 2], next_cursor: "c2"), page([1, 2], has_more: true)].each do |first|
      walk = paginator(:getPaRegistrations, responses: [first, page([3])]).items

      error = assert_raises(PennylaneClient::Error) { walk.to_a }
      assert_match(/getPaRegistrations.*has_more/, error.message)
      assert_equal 1, @transport.requests.size
    end
  end

  def test_refuses_an_operation_that_cannot_return_a_list
    assert_raises(ArgumentError) { paginator(:postJournals) }
  end

  def test_raises_when_the_cursor_does_not_move
    looping = [page([1], next_cursor: "c2"), page([2], next_cursor: "c2"), page([3])]

    assert_raises(PennylaneClient::Error) { paginator(:getCustomerInvoices, responses: looping).items.to_a }
  end

  def test_raises_when_a_response_is_not_a_page
    error = assert_raises(PennylaneClient::Error) { paginator(:getJournal, { id: 1 }, responses: [ok(200, '{"id":1}')]).items.to_a }
    assert_match(/getJournal/, error.message)
  end
end
