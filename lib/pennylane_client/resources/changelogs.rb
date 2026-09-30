# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Changelogs: `client.changelogs`, one feed of insert, update and delete
    # events per record type, oldest `processed_at` first.
    #
    # Each method returns an Enumerator::Lazy of change Hashes (`id`,
    # `operation`, `processed_at`, `created_at`, `updated_at`). Pennylane
    # keeps four weeks of changes: `since:` older than that is a 422. With no
    # `since:` the feed starts at the oldest change kept. `since:` takes a
    # Time or an RFC 3339 String and is sent with the first page only;
    # Pennylane answers 400 to `start_date` next to a `cursor`.
    #
    # To pick up where the last run stopped, pass the `processed_at` of the
    # last change handled as `since:`; the last page's `next_cursor` is null.
    #
    # `since:` is the only spelling. Pennylane's name for it, `start_date:`,
    # raises ArgumentError, so there is one way to say it.
    #
    #   client.changelogs.customer_invoices(since: Time.now - 3600).each { |change| sync(change[:id]) }
    class Changelogs < Resource
      # Customer invoice changes.
      def customer_invoices(since: nil, **params) = feed(:getCustomerInvoicesChanges, since, params)

      # Customer changes.
      def customers(since: nil, **params) = feed(:getCustomerChanges, since, params)

      # Changes to the categories of ledger entries.
      def ledger_entries_categories(since: nil, **params)
        feed(:getLedgerEntriesCategoryChanges, since, params)
      end

      # Ledger entry line changes.
      def ledger_entry_lines(since: nil, **params) = feed(:getLedgerEntryLineChanges, since, params)

      # Changes to the categories of ledger entry lines.
      def ledger_entry_lines_categories(since: nil, **params)
        feed(:getLedgerEntryLinesCategoryChanges, since, params)
      end

      # Product changes.
      def products(since: nil, **params) = feed(:getProductChanges, since, params)

      # Quote changes. Pennylane tags this one Quotes; it is a changelog feed
      # like the rest.
      def quotes(since: nil, **params) = feed(:getQuoteChanges, since, params)

      # Supplier invoice changes.
      def supplier_invoices(since: nil, **params) = feed(:getSupplierInvoicesChanges, since, params)

      # Supplier changes.
      def suppliers(since: nil, **params) = feed(:getSupplierChanges, since, params)

      # Transaction changes.
      def transactions(since: nil, **params) = feed(:getTransactionChanges, since, params)

      private

      # A String key counts too: "start_date" would go next to the one from
      # since:, and "since" would go as a param Pennylane does not take.
      def feed(operation_id, since, params)
        keys = params.keys.map(&:to_s)
        raise ArgumentError, "changelogs take since:, not start_date:" if keys.include?("start_date")
        raise ArgumentError, "changelogs take since: as a keyword, not a String key" if keys.include?("since")

        paginate(operation_id, start_date: since, **params)
      end
    end
  end
end
