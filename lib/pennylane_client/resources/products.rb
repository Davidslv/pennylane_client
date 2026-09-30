# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Products: `client.products`, the catalogue that invoice and quote
    # lines can point at with `product_id:`.
    #
    # Attributes go to Pennylane as given, through the Encoder (a BigDecimal
    # price becomes "650.5"). Responses are deep-frozen Hashes.
    class Products < Resource
      # Every product, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page. The filter takes `id`, `label`, `reference` and
      # `external_reference`; `sort:` takes `id`.
      #
      #   products.list(filter: [{ field: "reference", operator: "eq", value: "SKU-1" }])
      def list(**params) = paginate(:getProducts, **params)

      # One product.
      def find(id) = call(:getProduct, id:)

      # Creates a product. Pennylane requires `label:`, `price_before_tax:`
      # and `vat_rate:` (a code such as "FR_200" for 20% French VAT).
      #
      #   products.create(label: "Consulting day", price_before_tax: BigDecimal("650"), vat_rate: "FR_200")
      def create(retry: nil, **attributes) = call(:postProducts, retry:, **attributes)

      # Updates a product. Only the attributes you pass change.
      def update(id, retry: nil, **attributes) = call_on(:putProduct, { id: }, retry:, **attributes)
    end
  end
end
