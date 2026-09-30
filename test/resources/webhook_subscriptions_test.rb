# frozen_string_literal: true

require "test_helper"

# Webhook subscriptions: `client.webhook_subscriptions`. Each stub is the
# method and path from the operation's reference page.
class WebhookSubscriptionsTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def webhooks = client.webhook_subscriptions

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    assert_same client.webhook_subscriptions, client.webhook_subscriptions
    refute_includes client.webhook_subscriptions.inspect, "tok"
  end

  # names: getWebhookSubscriptions
  def test_list_walks_every_page
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/webhook_subscriptions").with(query: { limit: "100" })
                                                      .to_return(status: 200, body: first)
    stub_request(:get, "#{API}/webhook_subscriptions").with(query: { limit: "100", cursor: "c2" })
                                                      .to_return(status: 200, body: page(2))

    assert_equal [1, 2], webhooks.list.map { _1[:id] }.to_a
  end

  # names: getWebhookSubscription
  def test_find
    stub_request(:get, "#{API}/webhook_subscriptions/6").to_return(status: 200, body: '{"id":6,"enabled":true}')

    assert_equal({ id: 6, enabled: true }, webhooks.find(6))
  end

  # names: postWebhookSubscriptions
  def test_create_returns_the_secret
    body = '{"callback_url":"https://example.com/hooks","events":["dms_file.created"]}'
    stub_request(:post, "#{API}/webhook_subscriptions").with(body:)
                                                       .to_return(status: 201, body: '{"id":6,"secret":"whsec"}')

    created = webhooks.create(callback_url: "https://example.com/hooks", events: ["dms_file.created"])

    assert_equal "whsec", created[:secret]
  end

  # names: putWebhookSubscription
  def test_update
    stub_request(:put, "#{API}/webhook_subscriptions/6").with(body: '{"enabled":false}')
                                                        .to_return(status: 200, body: '{"id":6,"enabled":false}')

    assert_equal({ id: 6, enabled: false }, webhooks.update(6, enabled: false))
  end

  # names: deleteWebhookSubscription
  def test_delete
    stub_request(:delete, "#{API}/webhook_subscriptions/6").with(body: nil).to_return(status: 204)

    assert webhooks.delete(6)
  end
end
