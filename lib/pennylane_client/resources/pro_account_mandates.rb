# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Pro Account mandates: `client.pro_account_mandates`.
    #
    # Every method needs a Pennylane Pro Account and an enabled merchant
    # profile. Without the Pro Account, Pennylane answers 404
    # (NotFoundError); without the merchant profile, 403 (PermissionError).
    # `getCompanyFeatures` shows what the company has.
    #
    # Attributes go to Pennylane as given, keyword for keyword, through the
    # Encoder. Responses are deep-frozen Hashes.
    class ProAccountMandates < Resource
      # Every Pro Account payment mandate, as an Enumerator::Lazy of Hashes.
      # Follows `next_cursor` as far as you read and sends `filter` and
      # `sort` again on every page.
      def list(**params) = paginate(:getProAccountMandates, **params)

      # Sends a customer a request for a Pro Account SEPA Direct Debit
      # mandate.
      def send_request(customer_id:, **fields)
        call(:postProAccountMandateMailRequests, customer_id:, **fields)
      end

      # The mandates that can be migrated to the Pro Account, as an
      # Enumerator::Lazy of Hashes.
      def migration_candidates(**params) = paginate(:getProAccountMandateMigrations, **params)

      # Migrates a mandate to the Pro Account. `mandate_type` is
      # "SepaMandate", or "Mandate" for a GoCardless one. Only a candidate
      # with status "available" can migrate.
      #
      #   pro_account_mandates.migrate(mandate_type: "SepaMandate", mandate_id: 3)
      def migrate(mandate_type:, mandate_id:, **fields)
        call(:postProAccountMandateMigrations, mandate_type:, mandate_id:, **fields)
      end
    end
  end
end
