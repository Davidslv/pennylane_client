# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Customer invoices and credit notes: `client.customer_invoices`.
    #
    # Attributes go to Pennylane as given, keyword for keyword, through the
    # Encoder (a BigDecimal becomes "12.5", a Date "2026-09-30"). Responses
    # are deep-frozen Hashes; an action Pennylane answers with no content
    # returns true.
    class CustomerInvoices < Resource
      # Every customer invoice and credit note, as an Enumerator::Lazy of
      # Hashes. Follows `next_cursor` as far as you read and sends `filter`
      # and `sort` again on every page.
      #
      #   invoices.list(filter: [{ field: "status", operator: "eq", value: "draft" }], sort: "-id")
      def list(**params) = paginate(:getCustomerInvoices, **params)

      # One customer invoice or credit note.
      def find(id) = call(:getCustomerInvoice, id:)

      # Creates a draft or finalized customer invoice or credit note.
      def create(**attributes) = call(:postCustomerInvoices, **attributes)

      # Updates a customer invoice. Only the attributes you pass change.
      def update(id, **attributes) = call_on(:updateCustomerInvoice, { id: }, **attributes)

      # Deletes a draft invoice or draft credit note. Returns true.
      def delete(id) = call(:deleteCustomerInvoices, id:)

      # Creates an invoice from a quote, which gives it its customer and
      # lines. Pennylane requires `quote_id:` and `draft:`.
      def create_from_quote(**attributes) = call(:createCustomerInvoiceFromQuote, **attributes)

      # Imports an invoice issued elsewhere, with its PDF already uploaded
      # (`file_attachment_id:`). Pennylane stores the amounts exactly as
      # sent, so they must add up.
      def import(**attributes) = call(:importCustomerInvoices, **attributes)

      # Imports an invoice from an e-invoice file: a Factur-X PDF, or a UBL or
      # CII XML invoice (alpha at Pennylane). `file` is a File, IO, Pathname
      # or PennylaneClient::Upload and streams from disk. Hash and Array
      # fields (`invoice_options:`, `installments:`) go as JSON parts.
      def import_e_invoice(file, **fields) = call(:createCustomerInvoiceEInvoiceImport, file:, **fields)

      # Turns a draft into a finalized invoice, which can no longer be edited.
      def finalize(id) = call(:finalizeCustomerInvoice, id:)

      # Marks an invoice as paid. Pennylane reconciles nothing. Returns true.
      def mark_as_paid(id) = call(:markAsPaidCustomerInvoice, id:)

      # Marks one installment as paid; the invoice is paid once all of them
      # are. Pennylane tags this operation Hidden and calls it alpha, so it
      # may change. Returns true.
      def mark_installment_as_paid(customer_invoice_id, id)
        call(:markAsPaidCustomerInvoiceInstallment, customer_invoice_id:, id:)
      end

      # Emails a finalized or imported invoice. With no `recipients:`,
      # Pennylane uses the customer's addresses. Raises ConflictError while
      # the PDF is still being generated; try again in a few minutes.
      # Returns true.
      def send_by_email(id, **fields) = call_on(:sendByEmailCustomerInvoice, { id: }, **fields)

      # Sends an e-invoice to the Partner Dematerialization Platform (PA).
      # Raises ConflictError while an e-invoice import is still processing;
      # try again in a few seconds. Returns true.
      def send_to_pa(id) = call(:sendToPaCustomerInvoice, id:)

      # Links a credit note to the invoice `id`:
      #
      #   invoices.link_credit_note(42, credit_note_id: 43)
      def link_credit_note(id, credit_note_id:) = call(:linkCreditNote, id:, credit_note_id:)

      # Matches one bank transaction to the invoice. Not for drafts. Call it
      # once per transaction; a transaction can match several invoices.
      # Returns true.
      #
      #   invoices.match_transaction(42, transaction_id: 9)
      def match_transaction(customer_invoice_id, transaction_id:)
        call(:postCustomerInvoiceMatchedTransactions, customer_invoice_id:, transaction_id:)
      end

      # Unmatches the transaction `transaction_id` from the invoice. Not for
      # drafts. Returns true.
      #
      #   invoices.unmatch_transaction(42, transaction_id: 9)
      def unmatch_transaction(customer_invoice_id, transaction_id:)
        call(:deleteCustomerInvoiceMatchedTransactions, customer_invoice_id:, id: transaction_id)
      end

      # Updates an imported invoice or credit note (not a draft).
      def update_imported(id, **attributes) = call_on(:updateImportedCustomerInvoice, { id: }, **attributes)

      # The lists below hang off one invoice. Each returns every item as an
      # Enumerator::Lazy of Hashes, like `list`, and takes `sort:` or a
      # smaller `limit:` where Pennylane does.

      # The invoice's lines. Takes `sort:`.
      def invoice_lines(customer_invoice_id, **params)
        paginate_on(:getCustomerInvoiceInvoiceLines, { customer_invoice_id: }, **params)
      end

      # The sections that group the invoice's lines. Takes `sort:`.
      def invoice_line_sections(customer_invoice_id, **params)
        paginate_on(:getCustomerInvoiceInvoiceLineSections, { customer_invoice_id: }, **params)
      end

      # Payments received against the invoice. Takes `sort:`.
      def payments(customer_invoice_id, **params)
        paginate_on(:getCustomerInvoicePayments, { customer_invoice_id: }, **params)
      end

      # Bank transactions matched to the invoice. Takes `sort:`.
      def matched_transactions(customer_invoice_id, **params)
        paginate_on(:getCustomerInvoiceMatchedTransactions, { customer_invoice_id: }, **params)
      end

      # The invoice's custom header fields. Takes `sort:`.
      def custom_header_fields(customer_invoice_id, **params)
        paginate_on(:getCustomerInvoiceCustomHeaderFields, { customer_invoice_id: }, **params)
      end

      # Files attached to the invoice as appendices (not in the DMS). No `sort:`.
      def appendices(customer_invoice_id, **params)
        paginate_on(:getCustomerInvoiceAppendices, { customer_invoice_id: }, **params)
      end

      # Attaches `file` (a PDF or image: File, IO, Pathname or
      # PennylaneClient::Upload) as an appendix. It streams from disk.
      def upload_appendix(customer_invoice_id, file)
        call(:postCustomerInvoiceAppendices, customer_invoice_id:, file:)
      end

      # The analytical categories the invoice is split across. No `sort:`.
      def categories(customer_invoice_id, **params)
        paginate_on(:getCustomerInvoiceCategories, { customer_invoice_id: }, **params)
      end

      # Replaces the invoice's categories. `categories` is an Array of
      # `{ id:, weight: }`; within one category group the weights must add up
      # to 1. Not for drafts.
      #
      #   invoices.categorize(42, [{ id: 426, weight: "0.6575" }, { id: 427, weight: "0.3425" }])
      def categorize(customer_invoice_id, categories)
        call(:putCustomerInvoiceCategories, categories, customer_invoice_id:)
      end
    end
  end
end
