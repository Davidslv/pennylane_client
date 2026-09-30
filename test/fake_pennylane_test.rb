# frozen_string_literal: true

require "test_helper"
require "support/fake_pennylane_helpers"
require "stringio"

class FakePennylaneTest < Minitest::Test
  include FakePennylaneHelpers

  def test_answers_with_json_and_the_rate_limit_headers
    response = get

    assert_equal [200, "25", "24", "1770379505", nil], summary(response)
    assert_equal({ "id" => 1 }, JSON.parse(response.body))
  end

  def test_the_26th_request_in_a_window_is_a_429_with_retry_after
    25.times { assert_equal 200, get.status }
    @time.sleeper.call(3.2)
    response = get

    assert_equal [429, "25", "0", "1770379505", "2"], summary(response)
    assert_equal "Rate limit exceeded. Please retry in 2 seconds.", response.body
  end

  def test_the_window_resets_on_the_reported_second
    25.times { get }
    @time.sleeper.call(4.999)

    assert_equal 429, get.status
    @time.sleeper.call(0.001)

    assert_equal [200, "25", "24", "1770379510", nil], summary(get)
  end

  # Pennylane counts per token (guides/rate-limiting.md).
  def test_each_token_has_its_own_budget
    25.times { get(token: "a") }

    assert_equal 429, get(token: "a").status
    assert_equal 200, get(token: "b").status
  end

  def test_a_request_without_a_token_is_unauthorized
    response = @fake.call(request(:get, "/me", token: nil))

    assert_equal 401, response.status
    assert_nil response.headers["ratelimit-remaining"]
  end

  def test_counts_answers_by_verb_and_status
    26.times { get }
    @fake.call(request(:post, "/customer_invoices", token: "other", body: "{}"))

    assert_equal 25, @fake.count("GET 200")
    assert_equal 1, @fake.count("GET 429")
    assert_equal 1, @fake.count("POST 200")
    assert_equal 27, @fake.requests
  end

  def test_serves_a_collection_in_cursor_pages
    @fake.collection("/api/external/v2/customer_invoices", size: 5)

    first = page("/customer_invoices?limit=2")
    last = page("/customer_invoices?limit=4&cursor=#{first.fetch("next_cursor")}")

    assert_equal [[1, 2], true], [ids(first), first.fetch("has_more")]
    assert_equal [[3, 4, 5], false, nil], [ids(last), last.fetch("has_more"), last.fetch("next_cursor")]
  end

  def page(path) = JSON.parse(get(path).body)

  def ids(page) = page.fetch("items").map { _1.fetch("id") }

  def test_an_unknown_cursor_is_invalid
    @fake.collection("/api/external/v2/customer_invoices", size: 5)

    assert_equal 400, get("/customer_invoices?cursor=nope").status
  end

  def test_a_client_paginates_the_whole_collection
    @fake.collection("/api/external/v2/customer_invoices", size: 250)

    ids = client.paginate(:getCustomerInvoices).map { _1[:id] }.to_a

    assert_equal (1..250).to_a, ids
    assert_equal 3, @fake.count("GET 200")
  end

  def test_reads_an_upload_to_the_end_and_answers_with_its_size
    form = PennylaneClient::Multipart.new(file: StringIO.new("x" * 70_000), label: "a")
    form.read(100)

    received = JSON.parse(@fake.call(request(:post, "/file_attachments", body: form)).body).fetch("received")

    assert_equal form.size, received
  end

  # The client's limiter and the fake agree: sequential calls never see a 429.
  def test_a_client_never_hits_the_limit
    @time.sleeper.call(2.5) # start mid-window
    100.times { client.call(:getMe) }

    assert_equal 0, @fake.count("GET 429")
    assert_equal 100, @fake.count("GET 200")
  end
end
