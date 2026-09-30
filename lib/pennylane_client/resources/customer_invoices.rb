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
      def update(id, **attributes) = call(:updateCustomerInvoice, id:, **attributes)

      # Deletes a draft invoice or draft credit note. Returns true.
      def delete(id) = call(:deleteCustomerInvoices, id:)

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
      def send_by_email(id, **fields) = call(:sendByEmailCustomerInvoice, id:, **fields)

      # Sends an e-invoice to the Partner Dematerialization Platform (PA).
      # Raises ConflictError while an e-invoice import is still processing;
      # try again in a few seconds. Returns true.
      def send_to_pa(id) = call(:sendToPaCustomerInvoice, id:)

      # Links the credit note `credit_note_id` to the invoice `id`.
      def link_credit_note(id, credit_note_id) = call(:linkCreditNote, id:, credit_note_id:)

      # Updates an imported invoice or credit note (not a draft).
      def update_imported(id, **attributes) = call(:updateImportedCustomerInvoice, id:, **attributes)
    end
  end
end
