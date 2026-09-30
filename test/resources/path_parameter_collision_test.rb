# frozen_string_literal: true

require "test_helper"

# A named method takes its path parameters positionally. A keyword naming
# one of them (a fetched record merged back in, say) must raise, not
# replace the positional id and write to another record.
class PathParameterCollisionTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)

  def setup
    @any = stub_request(:any, /#{Regexp.escape(API)}/o).to_return(status: 200, body: "{}")
  end

  def test_update_refuses_an_id_in_the_attributes
    error = assert_raises(ArgumentError) { client.products.update(1, id: 2, label: "Widget") }

    assert_equal "putProduct takes id positionally; it cannot also be a keyword", error.message
    assert_not_requested @any
  end

  def test_update_refuses_a_string_id_in_the_attributes
    assert_raises(ArgumentError) { client.products.update(1, **{ "id" => 2 }) }
    assert_not_requested @any
  end

  def test_nested_create_refuses_the_parent_id_in_the_attributes
    assert_raises(ArgumentError) { client.customers.create_contact(1, customer_id: 2, first_name: "Ada") }
    assert_not_requested @any
  end

  def test_nested_update_refuses_either_id_in_the_attributes
    assert_raises(ArgumentError) { client.customers.update_contact(1, 5, id: 6) }
    assert_raises(ArgumentError) { client.customers.update_contact(1, 5, customer_id: 2) }
    assert_not_requested @any
  end

  def test_an_action_refuses_an_id_in_the_fields
    assert_raises(ArgumentError) { client.customer_invoices.send_by_email(1, id: 2) }
    assert_not_requested @any
  end

  def test_a_nested_list_refuses_the_parent_id_in_the_params
    assert_raises(ArgumentError) { client.customer_invoices.invoice_lines(1, customer_invoice_id: 2) }
    assert_not_requested @any
  end

  def test_an_update_without_a_collision_still_sends
    client.products.update(1, label: "Widget")

    assert_requested :put, "#{API}/products/1", body: '{"label":"Widget"}'
  end
end

# client.call takes every path parameter as a keyword, so the collision
# there is a positional Hash body that also names one.
class ClientPathParameterCollisionTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)

  def setup
    @any = stub_request(:any, /#{Regexp.escape(API)}/o).to_return(status: 200, body: "{}")
  end

  def test_refuses_a_body_that_names_a_path_parameter
    error = assert_raises(ArgumentError) { client.call(:putProduct, { id: 2, label: "Widget" }, id: 1) }

    assert_equal "the body names the path parameter [:id] of :putProduct; pass it only as a keyword", error.message
    assert_not_requested @any
  end

  def test_refuses_a_body_with_a_string_key_that_names_a_path_parameter
    assert_raises(ArgumentError) { client.call(:putProduct, { "id" => 2 }, id: 1) }
    assert_not_requested @any
  end

  def test_an_array_body_is_not_checked_for_keys
    client.call(:putCustomerCategories, [{ id: 1, weight: "1" }], customer_id: 9)

    assert_requested :put, "#{API}/customers/9/categories", body: '[{"id":1,"weight":"1"}]'
  end
end
