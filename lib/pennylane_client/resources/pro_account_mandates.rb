# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Pro Account mandates: `client.pro_account_mandates`.
    #
    # Every method needs a Pennylane Pro Account and an enabled merchant
    # profile. Without the Pro Account, Pennylane answers 404
    # (NotFoundError); without the merchant profile, 403 (PermissionError).
    # `getCompanyFeatures` does not report either yet, so the error is the
    # check.
    #
    # Attributes go to Pennylane as given, keyword for keyword, through the
    # Encoder. Responses are deep-frozen Hashes.
    class ProAccountMandates < Resource
      # Every Pro Account payment mandate, as an Enumerator::Lazy of Hashes.
      # Follows `next_cursor` as far as you read and sends `filter` and
      # `sort` again on every page.
      def list(**params) = paginate(:getProAccountMandates, **params)

      # Sends a customer a request for a Pro Account SEPA Direct Debit
      # mandate. Returns true.
      def send_request(customer_id:) = call(:postProAccountMandateMailRequests, customer_id:)

      # The mandates that can be migrated to the Pro Account, as an
      # Enumerator::Lazy of Hashes.
      def migration_candidates(**params) = paginate(:getProAccountMandateMigrations, **params)

      # Migrates a mandate to the Pro Account. `mandate_type` is
      # "SepaMandate", or "Mandate" for a GoCardless one. Only a candidate
      # with status "available" can migrate. The answer wraps the migration
      # in `mandate_migration:`.
      #
      #   pro_account_mandates.migrate(mandate_type: "SepaMandate", mandate_id: 3)[:mandate_migration]
      def migrate(mandate_type:, mandate_id:, **fields)
        call(:postProAccountMandateMigrations, mandate_type:, mandate_id:, **fields)
      end
    end
  end
end
