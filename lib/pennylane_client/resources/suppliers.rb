# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Suppliers: `client.suppliers`.
    #
    # Attributes go to Pennylane as given, keyword for keyword, through the
    # Encoder. Responses are deep-frozen Hashes.
    class Suppliers < Resource
      # Every supplier, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page.
      #
      #   suppliers.list(filter: [{ field: "name", operator: "eq", value: "Acme" }])
      def list(**params) = paginate(:getSuppliers, **params)

      # One supplier.
      def find(id) = call(:getSupplier, id:)

      # Creates a supplier. Pennylane requires `name:`. Raises ConflictError
      # when the supplier already exists.
      def create(**attributes) = call(:postSupplier, **attributes)

      # Updates a supplier. Only the attributes you pass change.
      def update(id, **attributes) = call(:putSupplier, id:, **attributes)

      # The analytical categories the supplier is split across, as an
      # Enumerator::Lazy of Hashes. No `sort:`.
      def categories(supplier_id, **params) = paginate(:getSupplierCategories, supplier_id:, **params)

      # Replaces the supplier's categories. `categories` is an Array of
      # `{ id:, weight: }`; within one category group the weights must add up
      # to 1.
      #
      #   suppliers.categorize(12, [{ id: 426, weight: "0.6575" }, { id: 427, weight: "0.3425" }])
      def categorize(supplier_id, categories)
        call(:putSupplierCategories, categories, supplier_id:)
      end
    end
  end
end
