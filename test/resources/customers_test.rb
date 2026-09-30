# frozen_string_literal: true

require "test_helper"
require "bigdecimal"

# Shared by the Customers behaviour tests: a real Client, with WebMock as
# Pennylane. Each stub is the method and path from the operation's
# reference page.
module CustomersTestHelper
  API = "https://app.pennylane.com/api/external/v2"

  ADDRESS = { address: "8 rue de la paix", postal_code: "75002", city: "Paris", country_alpha2: "FR" }.freeze

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def customers = client.customers

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })
end

# Every customer, company or individual: list, find, create.
class CustomersTest < Minitest::Test
  include CustomersTestHelper

  def test_is_one_resource_per_client
    assert_same client.customers, client.customers
    refute_includes client.customers.inspect, "tok"
  end

  # names: getCustomers
  def test_list_walks_every_page_resending_the_filter
    companies = [{ field: "customer_type", operator: "eq", value: "company" }]
    query = { filter: JSON.generate(companies), sort: "-id", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/customers").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/customers").with(query: query.merge(cursor: "c2"))
                                          .to_return(status: 200, body: page(2))

    assert_equal [1, 2], customers.list(filter: companies, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getCustomer
  def test_find
    stub_request(:get, "#{API}/customers/7").to_return(status: 200, body: '{"id":7,"customer_type":"company"}')

    assert_equal({ id: 7, customer_type: "company" }, customers.find(7))
  end

  # names: postCustomer
  def test_create_sends_the_customer_type_with_the_attributes
    body = { customer_type: "individual", first_name: "Ada", last_name: "Lovelace", billing_address: ADDRESS }
    stub_request(:post, "#{API}/customers").with(body: JSON.generate(body)).to_return(status: 201, body: '{"id":8}')

    assert_equal({ id: 8 }, customers.create(customer_type: "individual", first_name: "Ada", last_name: "Lovelace",
                                             billing_address: ADDRESS))
  end

  def test_create_requires_a_customer_type
    assert_raises(ArgumentError) { customers.create(name: "Acme", billing_address: ADDRESS) }
  end

  def test_a_failure_raises_its_error
    stub_request(:get, "#{API}/customers/404").to_return(status: 404, body: '{"error":"not_found"}')

    assert_raises(PennylaneClient::NotFoundError) { customers.find(404) }
  end
end

# Company and individual customers, each with its own create, find and
# update.
class CompanyAndIndividualCustomersTest < Minitest::Test
  include CustomersTestHelper

  # names: postCompanyCustomer
  def test_create_company
    body = { name: "Acme", billing_address: ADDRESS, vat_number: "FR32123456789" }
    stub_request(:post, "#{API}/company_customers").with(body: JSON.generate(body))
                                                   .to_return(status: 201, body: '{"id":9}')

    assert_equal({ id: 9 }, customers.create_company(name: "Acme", billing_address: ADDRESS,
                                                     vat_number: "FR32123456789"))
  end

  # names: getCompanyCustomer
  def test_find_company
    stub_request(:get, "#{API}/company_customers/9").to_return(status: 200, body: '{"id":9,"name":"Acme"}')

    assert_equal({ id: 9, name: "Acme" }, customers.find_company(9))
  end

  # names: putCompanyCustomer
  def test_update_company
    stub_request(:put, "#{API}/company_customers/9").with(body: '{"payment_conditions":"30_days"}')
                                                    .to_return(status: 200, body: '{"id":9}')

    assert_equal({ id: 9 }, customers.update_company(9, payment_conditions: "30_days"))
  end

  # names: postIndividualCustomer
  def test_create_individual
    body = { first_name: "Ada", last_name: "Lovelace", billing_address: ADDRESS }
    stub_request(:post, "#{API}/individual_customers").with(body: JSON.generate(body))
                                                      .to_return(status: 201, body: '{"id":10}')

    assert_equal({ id: 10 }, customers.create_individual(first_name: "Ada", last_name: "Lovelace",
                                                         billing_address: ADDRESS))
  end

  # names: getIndividualCustomer
  def test_find_individual
    stub_request(:get, "#{API}/individual_customers/10").to_return(status: 200, body: '{"id":10,"first_name":"Ada"}')

    assert_equal({ id: 10, first_name: "Ada" }, customers.find_individual(10))
  end

  # names: putIndividualCustomer
  def test_update_individual
    stub_request(:put, "#{API}/individual_customers/10").with(body: '{"emails":["ada@example.org"]}')
                                                        .to_return(status: 200, body: '{"id":10}')

    assert_equal({ id: 10 }, customers.update_individual(10, emails: ["ada@example.org"]))
  end
end

# What hangs off one customer: its contacts and its categories.
class CustomerContactsAndCategoriesTest < Minitest::Test
  include CustomersTestHelper

  # names: getCustomerContacts
  def test_contacts_walks_every_page
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/customers/7/contacts")
      .with(query: { limit: "100", sort: "-id" })
      .to_return(status: 200, body: first)
    stub_request(:get, "#{API}/customers/7/contacts")
      .with(query: { limit: "100", sort: "-id", cursor: "c2" })
      .to_return(status: 200, body: page(2))

    assert_equal [1, 2], customers.contacts(7, sort: "-id").map { _1[:id] }.to_a
  end

  # names: getCustomerContact
  def test_find_contact
    stub_request(:get, "#{API}/customers/7/contacts/3").to_return(status: 200, body: '{"id":3,"first_name":"Grace"}')

    assert_equal({ id: 3, first_name: "Grace" }, customers.find_contact(7, 3))
  end

  # names: postCustomerContact
  def test_create_contact
    stub_request(:post, "#{API}/customers/7/contacts")
      .with(body: '{"first_name":"Grace","last_name":"Hopper","email":"grace@example.org"}')
      .to_return(status: 201, body: '{"id":3}')

    assert_equal({ id: 3 }, customers.create_contact(7, first_name: "Grace", last_name: "Hopper",
                                                        email: "grace@example.org"))
  end

  # names: putCustomerContact
  def test_update_contact
    stub_request(:put, "#{API}/customers/7/contacts/3").with(body: '{"role":"CFO"}')
                                                       .to_return(status: 200, body: '{"id":3}')

    assert_equal({ id: 3 }, customers.update_contact(7, 3, role: "CFO"))
  end

  # names: deleteCustomerContact
  def test_delete_contact_returns_true_on_no_content
    stub_request(:delete, "#{API}/customers/7/contacts/3").with(body: nil).to_return(status: 204)

    assert customers.delete_contact(7, 3)
  end

  # names: getCustomerCategories
  def test_categories_walks_every_page
    stub_request(:get, "#{API}/customers/7/categories").with(query: { limit: "100" })
                                                       .to_return(status: 200, body: page(1, 2))

    assert_equal [1, 2], customers.categories(7).map { _1[:id] }.to_a
  end

  # names: putCustomerCategories
  def test_categorize_sends_the_categories_as_a_bare_array
    stub_request(:put, "#{API}/customers/7/categories")
      .with(body: '[{"id":426,"weight":"0.6575"},{"id":427,"weight":"0.3425"}]')
      .to_return(status: 200, body: '[{"id":426},{"id":427}]')

    categories = [{ id: 426, weight: BigDecimal("0.6575") }, { id: 427, weight: "0.3425" }]

    assert_equal [{ id: 426 }, { id: 427 }], customers.categorize(7, categories)
  end
end
