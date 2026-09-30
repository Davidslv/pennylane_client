# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Ledger entries: `client.ledger_entries`. The lines of every entry,
    # lettering and line categories are on `client.ledger_entry_lines`.
    #
    # Attributes go to Pennylane as given, through the Encoder (a BigDecimal
    # becomes "12.5", a Date "2026-09-30"). Responses are deep-frozen
    # Hashes.
    class LedgerEntries < Resource
      # Every ledger entry, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page. The filter takes `id`, `date` and `journal_id`;
      # `sort:` takes `id` and `date`.
      #
      #   ledger_entries.list(filter: [{ field: "journal_id", operator: "eq", value: "4" }], sort: "-date")
      def list(**params) = paginate(:getLedgerEntries, **params)

      # One ledger entry.
      def find(id) = call(:getLedgerEntry, id:)

      # Creates a ledger entry. Pennylane requires `date:`, `label:`,
      # `journal_id:` and `ledger_entry_lines:`, an Array of
      # `{ debit:, credit:, ledger_account_id: }` (up to 1000) that must
      # balance. The lines come back in any order: match them by content,
      # not position.
      #
      #   ledger_entries.create(date: Date.today, label: "Rent", journal_id: 4,
      #                         ledger_entry_lines: [{ debit: "1200", credit: "0", ledger_account_id: 21 },
      #                                              { debit: "0", credit: "1200", ledger_account_id: 7 }])
      def create(**attributes) = call(:postLedgerEntries, **attributes)

      # Updates a ledger entry. Only the attributes you pass change.
      # `ledger_entry_lines:` is `{ create: [...], update: [...], delete: [...] }`,
      # not a plain Array, and the result must still balance.
      def update(id, **attributes) = call_on(:putLedgerEntries, { id: }, **attributes)

      # The entry's lines, as an Enumerator::Lazy of Hashes. The filter
      # takes `ledger_account_id`; `sort:` takes `id`.
      def lines(ledger_entry_id, **params)
        paginate_on(:getLedgerEntriesLedgerEntryLines, { ledger_entry_id: }, **params)
      end
    end
  end
end
