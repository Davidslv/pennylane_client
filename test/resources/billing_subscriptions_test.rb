# frozen_string_literal: true

require "test_helper"

# Billing subscriptions: `client.billing_subscriptions`. Each stub is the
# method and path from the operation's reference page.
class BillingSubscriptionsTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def subscriptions = client.billing_subscriptions

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    assert_same client.billing_subscriptions, client.billing_subscriptions
    refute_includes client.billing_subscriptions.inspect, "tok"
  end

  # names: getBillingSubscriptions
  def test_list_walks_every_page_resending_the_filter
    in_progress = [{ field: "status", operator: "eq", value: "in_progress" }]
    query = { filter: JSON.generate(in_progress), limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/billing_subscriptions").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/billing_subscriptions").with(query: query.merge(cursor: "c2"))
                                                      .to_return(status: 200, body: page(2))

    assert_equal [1, 2], subscriptions.list(filter: in_progress).map { _1[:id] }.to_a
  end

  # names: getBillingSubscription
  def test_find
    stub_request(:get, "#{API}/billing_subscriptions/7").to_return(status: 200, body: '{"id":7,"status":"draft"}')

    assert_equal({ id: 7, status: "draft" }, subscriptions.find(7))
  end

  # names: postBillingSubscriptions
  def test_create_encodes_the_start_date_and_line_prices
    body = {
      start: "2026-10-01", customer_id: 3, payment_conditions: "30_days", payment_method: "offline",
      mode: { type: "finalized" }, recurring_rule: { type: "monthly", interval: 1, day_of_month: 1 },
      customer_invoice_data: { invoice_lines: [{ label: "Hosting", quantity: 1, unit: "month",
                                                 raw_currency_unit_price: "49.9", vat_rate: "FR_200" }] }
    }
    stub_request(:post, "#{API}/billing_subscriptions").with(body: JSON.generate(body))
                                                       .to_return(status: 201, body: '{"id":7}')

    line = { label: "Hosting", quantity: 1, unit: "month", raw_currency_unit_price: BigDecimal("49.9"),
             vat_rate: "FR_200" }
    created = subscriptions.create(start: Date.new(2026, 10, 1), customer_id: 3, payment_conditions: "30_days",
                                   payment_method: "offline", mode: { type: "finalized" },
                                   recurring_rule: { type: "monthly", interval: 1, day_of_month: 1 },
                                   customer_invoice_data: { invoice_lines: [line] })

    assert_equal({ id: 7 }, created)
  end

  # names: putBillingSubscriptions
  def test_update_stops_a_subscription
    stub_request(:put, "#{API}/billing_subscriptions/7").with(body: '{"stop":true}')
                                                        .to_return(status: 200, body: '{"id":7,"status":"stopped"}')

    assert_equal({ id: 7, status: "stopped" }, subscriptions.update(7, stop: true))
  end

  # names: getBillingSubscriptionInvoiceLines
  def test_invoice_lines
    stub_request(:get, "#{API}/billing_subscriptions/7/invoice_lines").with(query: { limit: "100" })
                                                                      .to_return(status: 200, body: page(11, 12))

    assert_equal [11, 12], subscriptions.invoice_lines(7).map { _1[:id] }.to_a
  end

  # names: getBillingSubscriptionInvoiceLineSections
  def test_invoice_line_sections
    stub_request(:get, "#{API}/billing_subscriptions/7/invoice_line_sections").with(query: { limit: "100" })
                                                                              .to_return(status: 200, body: page(4))

    assert_equal [4], subscriptions.invoice_line_sections(7).map { _1[:id] }.to_a
  end
end
