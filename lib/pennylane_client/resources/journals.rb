# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Journals: `client.journals`.
    #
    # Attributes go to Pennylane as given, through the Encoder. Responses
    # are deep-frozen Hashes.
    class Journals < Resource
      # Every journal, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page. The filter takes `type`; `sort:` takes `id`.
      #
      #   journals.list(sort: "id").map { _1[:code] }
      def list(**params) = paginate(:getJournals, **params)

      # One journal.
      def find(id) = call(:getJournal, id:)

      # Creates a journal. Pennylane requires `code:` (2 to 5 letters) and
      # `label:`.
      #
      #   journals.create(code: "BQ2", label: "Second bank")
      def create(**attributes) = call(:postJournals, **attributes)
    end
  end
end
