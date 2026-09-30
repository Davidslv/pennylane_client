# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Customer invoice templates: `client.customer_invoice_templates`. Read
    # only.
    class CustomerInvoiceTemplates < Resource
      # Every customer invoice template, as an Enumerator::Lazy of Hashes.
      # Takes `sort:`.
      def list(**params) = paginate(:getCustomerInvoiceTemplates, **params)
    end
  end
end
