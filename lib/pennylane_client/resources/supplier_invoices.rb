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
      # `deadline:`, the three currency amounts and `invoice_lines:`, and
      # stores the amounts exactly as sent, so they must add up.
      #
      # Raises ConflictError when the file was imported before: Pennylane
      # de-duplicates supplier invoice files. It raises ConflictError too
      # while the uploaded file is not ready yet; try again in a few
      # seconds. The client never retries a 409.
      def import(**attributes) = call(:importSupplierInvoice, **attributes)

      # Imports a supplier invoice from an e-invoice file: a Factur-X PDF, or
      # a UBL or CII XML invoice (alpha at Pennylane). `file` is a File, IO,
      # Pathname or PennylaneClient::Upload and streams from disk. Hash and
      # Array fields (`invoice_options:`, `override_invoice_lines:`) go as
      # JSON parts.
      def import_e_invoice(file, **fields) = call(:createSupplierInvoiceEInvoiceImport, file:, **fields)

      # Updates a supplier invoice. Only the attributes you pass change.
      # `invoice_lines:` takes `{ create:, update:, delete: }`.
      def update(id, **attributes) = call(:putSupplierInvoice, id:, **attributes)

      # Validates the invoice's accounting, which makes it complete.
      def validate_accounting(id) = call(:ValidateAccountingSupplierInvoice, id:)

      # Sets the payment status, `"paid"` or `"to_be_paid"`. Returns true.
      def update_payment_status(supplier_invoice_id, payment_status:)
        call(:updateSupplierInvoicePaymentStatus, supplier_invoice_id:, payment_status:)
      end

      # Moves an invoice received through the PA along its e-invoicing
      # lifecycle. `status:` is `"disputed"` or `"refused"`, each with a
      # `reason:`, or `"approved"` to lift a dispute. Refusing archives the
      # invoice for good. A transition the invoice cannot make raises
      # ValidationError.
      #
      #   invoices.update_e_invoice_status(42, status: "disputed", reason: "incorrect_vat_rate")
      def update_e_invoice_status(supplier_invoice_id, status:, **fields)
        call(:putSupplierInvoiceEInvoiceStatus, supplier_invoice_id:, status:, **fields)
      end

      # Links one purchase request to the invoice. Call it once per purchase
      # request. Returns true.
      def link_purchase_request(supplier_invoice_id, purchase_request_id:)
        call(:postSupplierInvoiceLinkedPurchaseRequests, supplier_invoice_id:, purchase_request_id:)
      end

      # The lists below hang off one invoice. Each returns every item as an
      # Enumerator::Lazy of Hashes, like `list`.

      # The invoice's lines. Takes `sort:`.
      def invoice_lines(supplier_invoice_id, **params)
        paginate(:getSupplierInvoiceLines, supplier_invoice_id:, **params)
      end

      # Payments made against the invoice. Takes `sort:`.
      def payments(supplier_invoice_id, **params)
        paginate(:getSupplierInvoicePayments, supplier_invoice_id:, **params)
      end

      # Bank transactions matched to the invoice. Takes `sort:`.
      def matched_transactions(supplier_invoice_id, **params)
        paginate(:getSupplierInvoiceMatchedTransactions, supplier_invoice_id:, **params)
      end

      # The analytical categories the invoice is split across. No `sort:`.
      def categories(supplier_invoice_id, **params)
        paginate(:getSupplierInvoiceCategories, supplier_invoice_id:, **params)
      end

      # Replaces the invoice's categories. `categories` is an Array of
      # `{ id:, weight: }`; within one category group the weights must add up
      # to 1.
      #
      #   invoices.categorize(42, [{ id: 426, weight: "0.6575" }, { id: 427, weight: "0.3425" }])
      def categorize(supplier_invoice_id, categories)
        call(:putSupplierInvoiceCategories, categories, supplier_invoice_id:)
      end
    end
  end
end
