# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Category groups: `client.category_groups`. A group holds analytical
    # categories (`client.categories`).
    #
    # Attributes go to Pennylane as given, through the Encoder. Responses
    # are deep-frozen Hashes.
    class CategoryGroups < Resource
      # Every category group, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read. Pennylane documents no filter or
      # sort here.
      def list(**params) = paginate(:getCategoryGroups, **params)

      # One category group.
      def find(id) = call(:getCategoryGroup, id:)

      # Creates a category group. Pennylane requires `label:`. `kind:` is
      # "profit_and_loss", "treasury" or "building".
      #
      #   category_groups.create(label: "Teams", kind: "profit_and_loss")
      def create(retry: nil, **attributes) = call(:postCategoryGroups, retry:, **attributes)

      # Updates a category group. Pennylane requires `label:` here too, even
      # when you change only `kind:`.
      def update(id, retry: nil, **attributes) = call_on(:putCategoryGroup, { id: }, retry:, **attributes)

      # The group's categories, as an Enumerator::Lazy of Hashes. Pennylane
      # documents no filter or sort here.
      def categories(category_group_id, **params)
        paginate_on(:getCategoryGroupCategories, { category_group_id: }, **params)
      end
    end
  end
end
