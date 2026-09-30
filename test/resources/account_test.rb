# frozen_string_literal: true

require "test_helper"

# The account the token belongs to: `client.users`, `client.company` and
# `client.pa_registrations`. Each stub is the method and path from the
# operation's reference page.
class AccountTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)

  def test_is_one_resource_per_client
    %i[users company pa_registrations].each do |name|
      assert_same client.public_send(name), client.public_send(name)
      refute_includes client.public_send(name).inspect, "tok"
    end
  end

  # names: getMe
  def test_me
    body = '{"user":null,"company":{"id":1,"name":"Acme"},"scopes":["customer_invoices"]}'
    stub_request(:get, "#{API}/me").to_return(status: 200, body:)

    assert_equal({ user: nil, company: { id: 1, name: "Acme" }, scopes: ["customer_invoices"] }, client.users.me)
  end

  # names: getCompanyFeatures
  def test_features
    stub_request(:get, "#{API}/company/features").to_return(status: 200, body: '{"installments":false}')

    refute client.company.features[:installments]
  end

  # names: getPaRegistrations
  def test_pa_registrations_returns_the_items
    body = JSON.generate({ items: [{ id: 1, siret: nil, status: "activated" }], has_more: false, next_cursor: nil })
    stub_request(:get, "#{API}/pa_registrations").to_return(status: 200, body:)

    assert_equal [{ id: 1, siret: nil, status: "activated" }], client.pa_registrations.list
  end
end
