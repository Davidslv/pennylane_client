# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Customers, company and individual: `client.customers`.
    #
    # Pennylane keeps the two kinds apart: a company has a `name`, an
    # individual a `first_name` and `last_name`. `list` and `find` see both.
    # Creating and updating one go through its own kind, with
    # `create_company` or `create_individual`. `create` is the one Pennylane
    # leaves undocumented (tagged Hidden): it makes either kind from
    # `customer_type:`.
    #
    # Attributes go to Pennylane as given, keyword for keyword, through the
    # Encoder. Responses are deep-frozen Hashes; an action Pennylane answers
    # with no content returns true.
    class Customers < Resource
      # Every customer, company and individual, as an Enumerator::Lazy of
      # Hashes. Follows `next_cursor` as far as you read and sends `filter`
      # and `sort` again on every page.
      #
      #   customers.list(filter: [{ field: "customer_type", operator: "eq", value: "company" }])
      def list(**params) = paginate(:getCustomers, **params)

      # One customer of either kind. Its `customer_type` says which.
      def find(id) = call(:getCustomer, id:)

      # Creates a customer of either kind, `"company"` or `"individual"`,
      # with that kind's attributes. Pennylane tags this operation Hidden, so
      # it may change; `create_company` and `create_individual` are the
      # documented way.
      #
      #   customers.create(customer_type: "company", name: "Acme", billing_address: { ... })
      def create(customer_type:, **attributes) = call(:postCustomer, customer_type:, **attributes)

      # Creates a company customer. Pennylane requires `name:` and
      # `billing_address:`.
      def create_company(**attributes) = call(:postCompanyCustomer, **attributes)

      # One company customer.
      def find_company(id) = call(:getCompanyCustomer, id:)

      # Updates a company customer. Only the attributes you pass change.
      def update_company(id, **attributes) = call(:putCompanyCustomer, id:, **attributes)

      # Creates an individual customer. Pennylane requires `first_name:`,
      # `last_name:` and `billing_address:`.
      def create_individual(**attributes) = call(:postIndividualCustomer, **attributes)

      # One individual customer.
      def find_individual(id) = call(:getIndividualCustomer, id:)

      # Updates an individual customer. Only the attributes you pass change.
      def update_individual(id, **attributes) = call(:putIndividualCustomer, id:, **attributes)

      # The customer's contacts, as an Enumerator::Lazy of Hashes, like
      # `list`. Takes `sort:`. A contact is its own record: it is not one of
      # the customer's invoice recipients (`emails`).
      def contacts(customer_id, **params) = paginate(:getCustomerContacts, customer_id:, **params)

      # One contact of the customer.
      def find_contact(customer_id, id) = call(:getCustomerContact, customer_id:, id:)

      # Adds a contact to the customer. Pennylane requires `first_name:`,
      # `last_name:` and `email:`. The email does not become an invoice
      # recipient.
      def create_contact(customer_id, **attributes)
        call(:postCustomerContact, customer_id:, **attributes)
      end

      # Updates a contact. Only the attributes you pass change.
      def update_contact(customer_id, id, **attributes)
        call(:putCustomerContact, customer_id:, id:, **attributes)
      end

      # Deletes a contact. The customer's invoice recipients stay as they
      # are. Returns true.
      def delete_contact(customer_id, id) = call(:deleteCustomerContact, customer_id:, id:)

      # The analytical categories the customer is split across, as an
      # Enumerator::Lazy of Hashes. No `sort:`.
      def categories(customer_id, **params) = paginate(:getCustomerCategories, customer_id:, **params)

      # Replaces the customer's categories. `categories` is an Array of
      # `{ id:, weight: }`; within one category group the weights must add up
      # to 1.
      #
      #   customers.categorize(7, [{ id: 426, weight: "0.6575" }, { id: 427, weight: "0.3425" }])
      def categorize(customer_id, categories)
        call(:putCustomerCategories, categories, customer_id:)
      end
    end
  end
end
