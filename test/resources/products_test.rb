# frozen_string_literal: true

require "test_helper"

# Products: `client.products`. Each stub is the method and path from the
# operation's reference page.
class ProductsTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def products = client.products

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    assert_same client.products, client.products
    refute_includes client.products.inspect, "tok"
  end

  # names: getProducts
  def test_list_walks_every_page_resending_the_filter
    by_reference = [{ field: "reference", operator: "eq", value: "SKU-1" }]
    query = { filter: JSON.generate(by_reference), limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/products").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/products").with(query: query.merge(cursor: "c2")).to_return(status: 200, body: page(2))

    assert_equal [1, 2], products.list(filter: by_reference).map { _1[:id] }.to_a
  end

  # names: getProduct
  def test_find
    stub_request(:get, "#{API}/products/5").to_return(status: 200, body: '{"id":5,"label":"Consulting day"}')

    assert_equal({ id: 5, label: "Consulting day" }, products.find(5))
  end

  # names: postProducts
  def test_create_encodes_a_big_decimal_price
    body = '{"label":"Consulting day","price_before_tax":"650.5","vat_rate":"FR_200"}'
    stub_request(:post, "#{API}/products").with(body:).to_return(status: 201, body: '{"id":5}')

    assert_equal({ id: 5 }, products.create(label: "Consulting day", price_before_tax: BigDecimal("650.5"),
                                            vat_rate: "FR_200"))
  end

  # names: putProduct
  def test_update
    stub_request(:put, "#{API}/products/5").with(body: '{"unit":"day"}')
                                           .to_return(status: 200, body: '{"id":5,"unit":"day"}')

    assert_equal({ id: 5, unit: "day" }, products.update(5, unit: "day"))
  end
end
