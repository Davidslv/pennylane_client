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
    #   client.changelogs.customer_invoices(since: Time.now - 3600).each { |change| sync(change[:id]) }
    class Changelogs < Resource
      # Customer invoice changes.
      def customer_invoices(since: nil, **params) = paginate(:getCustomerInvoicesChanges, start_date: since, **params)

      # Customer changes.
      def customers(since: nil, **params) = paginate(:getCustomerChanges, start_date: since, **params)

      # Changes to the categories of ledger entries.
      def ledger_entries_categories(since: nil, **params)
        paginate(:getLedgerEntriesCategoryChanges, start_date: since, **params)
      end

      # Ledger entry line changes.
      def ledger_entry_lines(since: nil, **params) = paginate(:getLedgerEntryLineChanges, start_date: since, **params)

      # Changes to the categories of ledger entry lines.
      def ledger_entry_lines_categories(since: nil, **params)
        paginate(:getLedgerEntryLinesCategoryChanges, start_date: since, **params)
      end

      # Product changes.
      def products(since: nil, **params) = paginate(:getProductChanges, start_date: since, **params)

      # Quote changes. Pennylane tags this one Quotes; it is a changelog feed
      # like the rest.
      def quotes(since: nil, **params) = paginate(:getQuoteChanges, start_date: since, **params)

      # Supplier invoice changes.
      def supplier_invoices(since: nil, **params) = paginate(:getSupplierInvoicesChanges, start_date: since, **params)

      # Supplier changes.
      def suppliers(since: nil, **params) = paginate(:getSupplierChanges, start_date: since, **params)

      # Transaction changes.
      def transactions(since: nil, **params) = paginate(:getTransactionChanges, start_date: since, **params)
    end
  end
end
