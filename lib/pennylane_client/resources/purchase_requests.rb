# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Purchase requests: `client.purchase_requests`.
    #
    # Attributes go to Pennylane as given, through the Encoder (a BigDecimal
    # amount becomes "120.0"). Responses are deep-frozen Hashes.
    class PurchaseRequests < Resource
      # Every purchase request, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page. The filter takes `id`, `supplier_id`, `user_id` and
      # `reviewed_by_id`; `sort:` takes `id`.
      #
      #   purchase_requests.list(filter: [{ field: "supplier_id", operator: "eq", value: "4" }])
      def list(**params) = paginate(:getPurchaseRequests, **params)

      # One purchase request.
      def find(id) = call(:getPurchaseRequest, id:)

      # Imports a purchase order: creates a purchase request with the order
      # attached, already approved. The body is JSON, not a file: upload the
      # PDF with `client.file_attachments.upload` first and pass its id as
      # `file_attachment_id:`. Pennylane also requires `supplier_id:`,
      # `reason:`, `purchase_order_number:`, `currency_amount_before_tax:`,
      # `currency_amount:`, `currency_tax:`, `delivery_address:` and at
      # least one of `purchase_request_lines:`.
      def import(**attributes) = call(:createPurchaseRequestImport, **attributes)
    end
  end
end
