# frozen_string_literal: true

require "test_helper"

# Analytical categories and their groups: `client.categories`,
# `client.category_groups`. Each stub is the method and path from the
# operation's reference page.
class CategoriesTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def categories = client.categories
  def groups = client.category_groups

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    %i[categories category_groups].each do |name|
      assert_same client.public_send(name), client.public_send(name)
      refute_includes client.public_send(name).inspect, "tok"
    end
  end

  # names: getCategories
  def test_categories_list_walks_every_page_resending_the_filter
    in_group = [{ field: "category_group_id", operator: "eq", value: "3" }]
    query = { filter: JSON.generate(in_group), sort: "-id", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/categories").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/categories").with(query: query.merge(cursor: "c2")).to_return(status: 200, body: page(2))

    assert_equal [1, 2], categories.list(filter: in_group, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getCategory
  def test_categories_find
    stub_request(:get, "#{API}/categories/12").to_return(status: 200, body: '{"id":12,"label":"Marketing"}')

    assert_equal({ id: 12, label: "Marketing" }, categories.find(12))
  end

  # names: postCategories
  def test_categories_create
    stub_request(:post, "#{API}/categories").with(body: '{"label":"Marketing","category_group_id":3}')
                                            .to_return(status: 201, body: '{"id":12}')

    assert_equal({ id: 12 }, categories.create(label: "Marketing", category_group_id: 3))
  end

  # names: updateCategory
  def test_categories_update
    stub_request(:put, "#{API}/categories/12").with(body: '{"analytical_code":"MKT"}')
                                              .to_return(status: 200, body: '{"id":12,"analytical_code":"MKT"}')

    assert_equal({ id: 12, analytical_code: "MKT" }, categories.update(12, analytical_code: "MKT"))
  end

  # names: getCategoryGroups
  def test_groups_list_walks_every_page
    stub_request(:get, "#{API}/category_groups").with(query: { limit: "100" }).to_return(status: 200, body: page(3, 4))

    assert_equal [3, 4], groups.list.map { _1[:id] }.to_a
  end

  # names: getCategoryGroup
  def test_groups_find
    stub_request(:get, "#{API}/category_groups/3").to_return(status: 200, body: '{"id":3,"label":"Teams"}')

    assert_equal({ id: 3, label: "Teams" }, groups.find(3))
  end

  # names: postCategoryGroups
  def test_groups_create
    stub_request(:post, "#{API}/category_groups").with(body: '{"label":"Teams","kind":"profit_and_loss"}')
                                                 .to_return(status: 201, body: '{"id":3}')

    assert_equal({ id: 3 }, groups.create(label: "Teams", kind: "profit_and_loss"))
  end

  # names: putCategoryGroup
  def test_groups_update
    stub_request(:put, "#{API}/category_groups/3").with(body: '{"label":"Departments"}')
                                                  .to_return(status: 200, body: '{"id":3,"label":"Departments"}')

    assert_equal({ id: 3, label: "Departments" }, groups.update(3, label: "Departments"))
  end

  # names: getCategoryGroupCategories
  def test_groups_categories_walks_every_page
    stub_request(:get, "#{API}/category_groups/3/categories").with(query: { limit: "100" })
                                                             .to_return(status: 200, body: page(12, 13))

    assert_equal [12, 13], groups.categories(3).map { _1[:id] }.to_a
  end
end
