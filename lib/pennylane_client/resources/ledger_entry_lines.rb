# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Ledger entry lines: `client.ledger_entry_lines`. Lines are created and
    # changed through their entry (`client.ledger_entries`); here they are
    # listed, lettered and categorized.
    #
    # Responses are deep-frozen Hashes; `letter` returns an Array of them
    # and `unletter` returns true.
    class LedgerEntryLines < Resource
      # Every ledger entry line of the company, as an Enumerator::Lazy of
      # Hashes. Follows `next_cursor` as far as you read and sends `filter`
      # and `sort` again on every page. The filter takes `id`, `journal_id`,
      # `ledger_account_id` and `date`; `sort:` takes `id` and `date`.
      #
      #   ledger_entry_lines.list(filter: [{ field: "ledger_account_id", operator: "eq", value: "512" }])
      def list(**params) = paginate(:getLedgerEntryLines, **params)

      # One ledger entry line.
      def find(id) = call(:getLedgerEntryLine, id:)

      # Letters the lines together. `ledger_entry_lines` is an Array of
      # `{ id: }`, at least two. A line that is already lettered brings its
      # whole lettering along: lettering A (lettered with B) and C gives
      # A, B and C. `unbalanced_lettering_strategy:` is "none" (Pennylane
      # refuses an unbalanced lettering with a ValidationError) or
      # "partial". Returns every line of the new lettering.
      #
      #   ledger_entry_lines.letter([{ id: 91 }, { id: 95 }], unbalanced_lettering_strategy: "none")
      def letter(ledger_entry_lines, unbalanced_lettering_strategy:)
        call(:postLedgerEntryLinesLetter, ledger_entry_lines:, unbalanced_lettering_strategy:)
      end

      # Unletters the lines, an Array of `{ id: }`. Pennylane requires the
      # same `unbalanced_lettering_strategy:` as `letter`. Sent as a DELETE
      # with a JSON body. Returns true.
      def unletter(ledger_entry_lines, unbalanced_lettering_strategy:)
        call(:deleteLedgerEntryLinesUnletter, ledger_entry_lines:, unbalanced_lettering_strategy:)
      end

      # The lines lettered to this one, as an Enumerator::Lazy of Hashes.
      # `sort:` takes `id` and `date`.
      def lettered_lines(ledger_entry_line_id, **params)
        paginate(:getLedgerEntryLinesLetteredLedgerEntryLines, ledger_entry_line_id:, **params)
      end

      # The analytical categories the line is split across, as an
      # Enumerator::Lazy of Hashes. `sort:` takes `id`.
      def categories(ledger_entry_line_id, **params)
        paginate(:getLedgerEntryLinesCategories, ledger_entry_line_id:, **params)
      end

      # Replaces the line's categories. `categories` is an Array of
      # `{ id:, weight: }`, each weight a String between "0" and "1"; an
      # empty Array removes them all. Returns `{ ledger_entry_line: {...} }`.
      #
      #   ledger_entry_lines.categorize(91, [{ id: 59, weight: "0.5" }, { id: 33, weight: "0.5" }])
      def categorize(ledger_entry_line_id, categories)
        call(:putLedgerEntryLinesCategories, categories, ledger_entry_line_id:)
      end
    end
  end
end
