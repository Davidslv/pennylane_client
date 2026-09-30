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

    assert_equal({ installments: false }, client.company.features)
  end

  # names: getPaRegistrations
  def test_pa_registrations_list_is_lazy_like_every_other_list
    body = JSON.generate({ items: [{ id: 1, siret: nil, status: "activated" }], has_more: false, next_cursor: nil })
    stub = stub_request(:get, "#{API}/pa_registrations").to_return(status: 200, body:)
    list = client.pa_registrations.list

    assert_instance_of Enumerator::Lazy, list
    assert_not_requested stub
    assert_equal [{ id: 1, siret: nil, status: "activated" }], list.to_a
    assert_requested stub, times: 1
  end

  # Pennylane takes no cursor here, so a second page cannot be read. The
  # walk raises rather than loop or return part of the list.
  def test_pa_registrations_refuses_to_drop_a_second_page
    [{ has_more: true, next_cursor: "c2" }, { has_more: true, next_cursor: nil }].each do |more|
      body = JSON.generate({ items: [{ id: 1 }], **more })
      stub_request(:get, "#{API}/pa_registrations").to_return(status: 200, body:)

      error = assert_raises(PennylaneClient::Error) { client.pa_registrations.list.to_a }
      assert_match(/has_more/, error.message)
    end
  end
end
