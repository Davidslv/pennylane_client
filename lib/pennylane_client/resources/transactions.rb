# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Bank transactions: `client.transactions`.
    #
    # Matching a transaction to an invoice happens from the invoice's side:
    # `client.customer_invoices.match_transaction` and
    # `client.supplier_invoices.match_transaction`. `matched_invoices` here
    # lists what a transaction is matched to.
    #
    # Attributes go to Pennylane as given, keyword for keyword, through the
    # Encoder (a BigDecimal becomes "12.5", a Date "2026-09-30"). Responses
    # are deep-frozen Hashes.
    class Transactions < Resource
      # Every transaction, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page. The filter takes `id`, `bank_account_id`, `journal_id`
      # and `date`.
      #
      #   transactions.list(filter: [{ field: "bank_account_id", operator: "eq", value: "3" }])
      def list(**params) = paginate(:getTransactions, **params)

      # One transaction.
      def find(id) = call(:getTransaction, id:)

      # Creates a transaction in a bank account. Pennylane requires
      # `bank_account_id:`, `label:`, `date:` and `amount:`; `fee:` is
      # optional.
      #
      #   transactions.create(bank_account_id: 3, label: "Card payment", date: Date.today, amount: "-12.50")
      def create(**attributes) = call(:createTransaction, **attributes)

      # Sets the transaction's third party: pass either `customer_id:` or
      # `supplier_id:`, not both. Pennylane accepts nothing else here. Both
      # are nullable in the contract, so `nil` sends `null`.
      def update(id, **attributes) = call_on(:updateTransaction, { id: }, **attributes)

      # The analytical categories the transaction is split across, as an
      # Enumerator::Lazy of Hashes. No `sort:`.
      def categories(transaction_id, **params)
        paginate_on(:getTransactionCategories, { transaction_id: }, **params)
      end

      # Replaces the transaction's categories. `categories` is an Array of
      # `{ id:, weight: }`; within one category group the weights must add up
      # to 1, and categories from different groups can be mixed.
      #
      #   transactions.categorize(9, [{ id: 59, weight: "0.5" }, { id: 33, weight: "0.5" }, { id: 65, weight: "1" }])
      def categorize(transaction_id, categories)
        call(:putTransactionCategories, categories, transaction_id:)
      end

      # The customer and supplier invoices matched to the transaction, as an
      # Enumerator::Lazy of Hashes. No `sort:`.
      def matched_invoices(transaction_id, **params)
        paginate_on(:getTransactionMatchedInvoices, { transaction_id: }, **params)
      end
    end
  end
end
