# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Bank accounts: `client.bank_accounts`.
    #
    # A bank account comes back with its `journal` and `ledger_account`.
    # There is no update or delete.
    class BankAccounts < Resource
      # Every bank account, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read. Takes `sort:`; no filter.
      def list(**params) = paginate(:getBankAccounts, **params)

      # One bank account, with its `balance`.
      def find(id) = call(:getBankAccount, id:)

      # Creates a bank account. Pennylane requires `name:`; `iban:`, `bic:`,
      # `currency:`, `account_type:` and `bank_establishment_id:` are
      # optional. `account_type: "current"` is deprecated; use `"checking"`.
      #
      #   bank_accounts.create(name: "Main account", iban: "FR7630006000011234567890189")
      def create(**attributes) = call(:postBankAccount, **attributes)
    end
  end
end
