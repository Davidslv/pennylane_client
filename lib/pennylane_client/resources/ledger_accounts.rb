# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Ledger accounts: `client.ledger_accounts`.
    #
    # Attributes go to Pennylane as given, through the Encoder. Responses
    # are deep-frozen Hashes.
    class LedgerAccounts < Resource
      # Every ledger account, as an Enumerator::Lazy of Hashes, up to 1000 a
      # page. Follows `next_cursor` as far as you read and sends `filter`
      # and `sort` again on every page. The filter takes `id`, `number`
      # (`start_with`, `eq`, `in`) and `enabled`.
      #
      #   ledger_accounts.list(filter: [{ field: "number", operator: "start_with", value: "512" }])
      def list(**params) = paginate(:getLedgerAccounts, **params)

      # One ledger account.
      def find(id) = call(:getLedgerAccount, id:)

      # Creates a ledger account. Pennylane requires `number:` and `label:`.
      # A number starting with 401 also creates a supplier, and one starting
      # with 411 a company customer.
      #
      #   ledger_accounts.create(number: "6064", label: "Office supplies")
      def create(**attributes) = call(:postLedgerAccounts, **attributes)

      # Updates a ledger account: `label:` and `letterable:`, the only two
      # fields Pennylane accepts here.
      def update(id, **attributes) = call_on(:updateLedgerAccount, { id: }, **attributes)
    end
  end
end
