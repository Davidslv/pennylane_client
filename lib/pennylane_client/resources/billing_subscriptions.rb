# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Billing subscriptions: `client.billing_subscriptions`. Pennylane
    # issues a customer invoice for each occurrence of the recurring rule.
    #
    # The request and response shapes differ. You send `mode:` as a Hash
    # (`{ type: "finalized" }`) and `recurring_rule: { type: ... }`; you read
    # back `mode` as a String and `recurring_rule[:rule_type]`. Attributes go
    # to Pennylane as given, through the Encoder. Responses are deep-frozen
    # Hashes.
    class BillingSubscriptions < Resource
      # Every billing subscription, as an Enumerator::Lazy of Hashes.
      # Follows `next_cursor` as far as you read and sends `filter` and
      # `sort` again on every page. The filter takes `id`, `start`,
      # `customer_id` and `status`; `sort:` takes `id`.
      #
      #   billing_subscriptions.list(filter: [{ field: "status", operator: "eq", value: "in_progress" }])
      def list(**params) = paginate(:getBillingSubscriptions, **params)

      # One billing subscription.
      def find(id) = call(:getBillingSubscription, id:)

      # Creates a billing subscription. Pennylane requires `start:`,
      # `customer_id:`, `mode:`, `payment_conditions:`, `payment_method:`,
      # `recurring_rule:` and `customer_invoice_data:` with at least one
      # invoice line.
      #
      #   billing_subscriptions.create(start: Date.new(2026, 10, 1), customer_id: 3, mode: { type: "finalized" },
      #                                payment_conditions: "30_days", payment_method: "offline",
      #                                recurring_rule: { type: "monthly", interval: 1, day_of_month: 1 },
      #                                customer_invoice_data: { invoice_lines: [line] })
      def create(retry: nil, **attributes) = call(:postBillingSubscriptions, retry:, **attributes)

      # Updates a billing subscription. Only the attributes you pass change.
      # `stop: true` stops one in progress and `stop: false` resumes it.
      # Invoice lines and sections change through `create`, `update` and
      # `delete` lists inside `customer_invoice_data:`.
      def update(id, retry: nil, **attributes) = call_on(:putBillingSubscriptions, { id: }, retry:, **attributes)

      # The invoice lines of a billing subscription, as an
      # Enumerator::Lazy of Hashes.
      def invoice_lines(billing_subscription_id, **params)
        paginate_on(:getBillingSubscriptionInvoiceLines, { billing_subscription_id: }, **params)
      end

      # The invoice line sections of a billing subscription, as an
      # Enumerator::Lazy of Hashes.
      def invoice_line_sections(billing_subscription_id, **params)
        paginate_on(:getBillingSubscriptionInvoiceLineSections, { billing_subscription_id: }, **params)
      end
    end
  end
end
