# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Supplier invoices: `client.supplier_invoices`.
    #
    # A supplier invoice comes to exist by import only, from a file already
    # uploaded (`import`) or from an e-invoice file (`import_e_invoice`).
    #
    # Attributes go to Pennylane as given, keyword for keyword, through the
    # Encoder (a BigDecimal becomes "12.5", a Date "2026-09-30"). Responses
    # are deep-frozen Hashes; an action Pennylane answers with no content
    # returns true.
    class SupplierInvoices < Resource
      # Every supplier invoice, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page.
      #
      #   invoices.list(filter: [{ field: "payment_status", operator: "eq", value: "to_be_paid" }])
      def list(**params) = paginate(:getSupplierInvoices, **params)

      # One supplier invoice.
      def find(id) = call(:getSupplierInvoice, id:)

      # Imports a supplier invoice with its PDF already uploaded
      # (`file_attachment_id:`). Pennylane requires `supplier_id:`, `date:`,
      # `deadline:`, the three currency amounts and `invoice_lines:`.
      #
      # Raises ConflictError when the file was imported before: Pennylane
      # de-duplicates supplier invoice files. It raises ConflictError too
      # while the uploaded file is not ready yet; try again in a few
      # seconds. The client never retries a 409.
      def import(retry: nil, **attributes) = call(:importSupplierInvoice, retry:, **attributes)

      # Imports a supplier invoice from an e-invoice file: a Factur-X PDF, or
      # a UBL or CII XML invoice. `file` is a File, IO, Pathname or
      # PennylaneClient::Upload and streams from disk. Hash and Array fields
      # (`invoice_options:`, `override_invoice_lines:`) go as JSON parts.
      #
      # @note Experimental: the UBL and CII XML input only, which Pennylane
      #   calls alpha. It may change in a minor release (README, Stability).
      #   A Factur-X PDF is stable.
      def import_e_invoice(file, retry: nil, **fields)
        call_on(:createSupplierInvoiceEInvoiceImport, { file: }, retry:, **fields)
      end

      # Updates a supplier invoice. Only the attributes you pass change.
      # `invoice_lines:` takes `{ create:, update:, delete: }`.
      def update(id, retry: nil, **attributes) = call_on(:putSupplierInvoice, { id: }, retry:, **attributes)

      # Validates the invoice's accounting, which makes it complete.
      def validate_accounting(id, retry: nil) = call(:ValidateAccountingSupplierInvoice, id:, retry:)

      # Sets the payment status, `"paid"` or `"to_be_paid"`. Returns true.
      def update_payment_status(supplier_invoice_id, payment_status:, retry: nil)
        call(:updateSupplierInvoicePaymentStatus, supplier_invoice_id:, payment_status:, retry:)
      end

      # Moves an invoice received through the PA along its e-invoicing
      # lifecycle. `status:` is `"disputed"` or `"refused"`, each with a
      # `reason:`, or `"approved"` to lift a dispute. Refusing archives the
      # invoice for good. A transition the invoice cannot make raises
      # ValidationError.
      #
      #   invoices.update_e_invoice_status(42, status: "disputed", reason: "incorrect_vat_rate")
      def update_e_invoice_status(supplier_invoice_id, status:, retry: nil, **fields)
        call_on(:putSupplierInvoiceEInvoiceStatus, { supplier_invoice_id: }, status:, retry:, **fields)
      end

      # Links one purchase request to the invoice. Call it once per purchase
      # request. Returns true.
      def link_purchase_request(supplier_invoice_id, purchase_request_id:, retry: nil)
        call(:postSupplierInvoiceLinkedPurchaseRequests, supplier_invoice_id:, purchase_request_id:, retry:)
      end

      # Matches one bank transaction to the invoice. Call it once per
      # transaction; a transaction can match several invoices. Returns true.
      #
      #   invoices.match_transaction(42, transaction_id: 9)
      def match_transaction(supplier_invoice_id, transaction_id:, retry: nil)
        call(:postSupplierInvoiceMatchedTransactions, supplier_invoice_id:, transaction_id:, retry:)
      end

      # Unmatches the transaction `transaction_id` from the invoice. Returns
      # true.
      #
      #   invoices.unmatch_transaction(42, transaction_id: 9)
      def unmatch_transaction(supplier_invoice_id, transaction_id:, retry: nil)
        call(:deleteSupplierInvoiceMatchedTransactions, supplier_invoice_id:, id: transaction_id, retry:)
      end

      # The lists below hang off one invoice. Each returns every item as an
      # Enumerator::Lazy of Hashes, like `list`.

      # The invoice's lines. Takes `sort:`.
      def invoice_lines(supplier_invoice_id, **params)
        paginate_on(:getSupplierInvoiceLines, { supplier_invoice_id: }, **params)
      end

      # Payments made against the invoice. Takes `sort:`.
      def payments(supplier_invoice_id, **params)
        paginate_on(:getSupplierInvoicePayments, { supplier_invoice_id: }, **params)
      end

      # Bank transactions matched to the invoice. Takes `sort:`.
      def matched_transactions(supplier_invoice_id, **params)
        paginate_on(:getSupplierInvoiceMatchedTransactions, { supplier_invoice_id: }, **params)
      end

      # The analytical categories the invoice is split across. No `sort:`.
      def categories(supplier_invoice_id, **params)
        paginate_on(:getSupplierInvoiceCategories, { supplier_invoice_id: }, **params)
      end

      # Replaces the invoice's categories. `categories` is an Array of
      # `{ id:, weight: }`; within one category group the weights must add up
      # to 1.
      #
      #   invoices.categorize(42, [{ id: 426, weight: "0.6575" }, { id: 427, weight: "0.3425" }])
      def categorize(supplier_invoice_id, categories, retry: nil)
        call(:putSupplierInvoiceCategories, categories, supplier_invoice_id:, retry:)
      end
    end
  end
end
