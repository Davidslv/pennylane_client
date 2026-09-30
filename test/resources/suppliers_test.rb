# frozen_string_literal: true

require "test_helper"
require "bigdecimal"

# Shared by the Suppliers behaviour tests: a real Client, with WebMock as
# Pennylane. Each stub is the method and path from the operation's
# reference page.
module SuppliersTestHelper
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def suppliers = client.suppliers

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })
end

# The supplier itself, and its categories.
class SuppliersTest < Minitest::Test
  include SuppliersTestHelper

  def test_is_one_resource_per_client
    assert_same client.suppliers, client.suppliers
    refute_includes client.suppliers.inspect, "tok"
  end

  # names: getSuppliers
  def test_list_walks_every_page_resending_the_filter
    by_name = [{ field: "name", operator: "eq", value: "Acme" }]
    query = { filter: JSON.generate(by_name), sort: "-id", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/suppliers").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/suppliers").with(query: query.merge(cursor: "c2"))
                                          .to_return(status: 200, body: page(2))

    assert_equal [1, 2], suppliers.list(filter: by_name, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getSupplier
  def test_find
    stub_request(:get, "#{API}/suppliers/12").to_return(status: 200, body: '{"id":12,"name":"Acme"}')

    assert_equal({ id: 12, name: "Acme" }, suppliers.find(12))
  end

  # names: postSupplier
  def test_create
    stub_request(:post, "#{API}/suppliers")
      .with(body: '{"name":"Acme","supplier_payment_method":"manual_transfer","supplier_due_date_delay":30}')
      .to_return(status: 201, body: '{"id":12}')

    assert_equal({ id: 12 }, suppliers.create(name: "Acme", supplier_payment_method: "manual_transfer",
                                              supplier_due_date_delay: 30))
  end

  # Pennylane answers 409 when the supplier already exists.
  def test_create_of_an_existing_supplier_raises_conflict
    stub_request(:post, "#{API}/suppliers")
      .to_return(status: 409, body: '{"status":409,"error":"Resource already exists."}')

    assert_raises(PennylaneClient::ConflictError) { suppliers.create(name: "Acme", external_reference: "S-1") }
  end

  # names: putSupplier
  def test_update
    stub_request(:put, "#{API}/suppliers/12").with(body: '{"emails":["ap@acme.example"]}')
                                             .to_return(status: 200, body: '{"id":12}')

    assert_equal({ id: 12 }, suppliers.update(12, emails: ["ap@acme.example"]))
  end

  # names: getSupplierCategories
  def test_categories_walks_every_page
    stub_request(:get, "#{API}/suppliers/12/categories").with(query: { limit: "100" })
                                                        .to_return(status: 200, body: page(1, 2))

    assert_equal [1, 2], suppliers.categories(12).map { _1[:id] }.to_a
  end

  # names: putSupplierCategories
  def test_categorize_sends_the_categories_as_a_bare_array
    stub_request(:put, "#{API}/suppliers/12/categories")
      .with(body: '[{"id":426,"weight":"0.6575"},{"id":427,"weight":"0.3425"}]')
      .to_return(status: 200, body: '[{"id":426},{"id":427}]')

    categories = [{ id: 426, weight: BigDecimal("0.6575") }, { id: 427, weight: "0.3425" }]

    assert_equal [{ id: 426 }, { id: 427 }], suppliers.categorize(12, categories)
  end
end
