# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Analytical categories: `client.categories`. Every category belongs to
    # a category group (`client.category_groups`). To categorize an invoice,
    # transaction, customer, supplier or ledger entry line, use `categorize`
    # on that resource.
    #
    # Attributes go to Pennylane as given, through the Encoder. Responses
    # are deep-frozen Hashes.
    class Categories < Resource
      # Every category, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page. The filter takes `id`, `label`, `category_group_id`
      # and `analytical_code`; `sort:` takes `id`.
      #
      #   categories.list(filter: [{ field: "category_group_id", operator: "eq", value: "3" }])
      def list(**params) = paginate(:getCategories, **params)

      # One category.
      def find(id) = call(:getCategory, id:)

      # Creates a category. Pennylane requires `label:` and
      # `category_group_id:`. `direction:` applies to treasury categories
      # only and defaults to "cash_out".
      #
      #   categories.create(label: "Marketing", category_group_id: 3, analytical_code: "MKT")
      def create(retry: nil, **attributes) = call(:postCategories, retry:, **attributes)

      # Updates a category: `label:`, `analytical_code:` and `direction:`,
      # the only fields Pennylane accepts here. `category_group_id:` is not
      # one of them.
      def update(id, retry: nil, **attributes) = call_on(:updateCategory, { id: }, retry:, **attributes)
    end
  end
end
