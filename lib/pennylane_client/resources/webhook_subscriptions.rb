# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Webhook subscriptions: `client.webhook_subscriptions`. Pennylane POSTs
    # each subscribed event to `callback_url`, signed with the
    # subscription's secret. Webhooks are in beta at Pennylane; it suggests
    # the changelogs (`client.changelogs`) as the fallback.
    #
    # The events are `"customer_invoice.e_invoicing_status_updated"`,
    # `"dms_file.created"` and `"supplier_invoice.e_invoicing_received"`.
    # A company, or an app-bound token, has at most 10 subscriptions.
    class WebhookSubscriptions < Resource
      # Every webhook subscription of the token, as an Enumerator::Lazy of
      # Hashes. Follows `next_cursor` as far as you read. No secrets.
      def list(**params) = paginate(:getWebhookSubscriptions, **params)

      # One webhook subscription, without its secret. `enabled`,
      # `disabled_reason` and `consecutive_failures` say whether Pennylane
      # still delivers to it.
      def find(id) = call(:getWebhookSubscription, id:)

      # Creates a webhook subscription. Pennylane requires `callback_url:`
      # and `events:`; `enabled:` defaults to true. The response carries
      # `:secret`, the key for checking signatures. Store it now: Pennylane
      # never returns it again.
      #
      #   hook = webhook_subscriptions.create(callback_url: "https://example.com/hooks", events: ["dms_file.created"])
      #   store(hook[:secret])
      def create(retry: nil, **attributes) = call(:postWebhookSubscriptions, retry:, **attributes)

      # Updates a webhook subscription: `callback_url:`, `events:` or
      # `enabled:`. It takes no secret; a new subscription gets a new one.
      def update(id, retry: nil, **attributes) = call_on(:putWebhookSubscription, { id: }, retry:, **attributes)

      # Deletes a webhook subscription.
      def delete(id, retry: nil) = call(:deleteWebhookSubscription, id:, retry:)
    end
  end
end
