# frozen_string_literal: true

module PennylaneClient
  module Resources
    # GoCardless mandates: `client.gocardless_mandates`.
    #
    # Attributes go to Pennylane as given, keyword for keyword, through the
    # Encoder. Responses are deep-frozen Hashes.
    class GocardlessMandates < Resource
      # Every GoCardless mandate, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page.
      def list(**params) = paginate(:getGocardlessMandates, **params)

      # One GoCardless mandate.
      def find(id) = call(:getGocardlessMandate, id:)

      # Emails a customer a link to set up a GoCardless mandate. `email` is
      # `{ recipients: [...], subject:, body: }`; only `recipients` is
      # required. Returns true.
      #
      #   gocardless_mandates.send_request(customer_id: 7, email: { recipients: ["billing@acme.example"] })
      def send_request(customer_id:, email:, retry: nil)
        call(:postGocardlessMandateMailRequests, customer_id:, email:, retry:)
      end

      # Associates the mandate with a customer. Returns true.
      def associate(gocardless_mandate_id, customer_id:, retry: nil)
        call(:postGocardlessMandateAssociations, gocardless_mandate_id:, customer_id:, retry:)
      end

      # Cancels the mandate. Only a `pending_submission`, `submitted` or
      # `active` mandate can be cancelled. Pennylane rejects any other with a
      # 400 or 422, both ValidationError. Returns true.
      def cancel(gocardless_mandate_id, retry: nil)
        call(:postGocardlessMandateCancellations, gocardless_mandate_id:, retry:)
      end
    end
  end
end
