# frozen_string_literal: true

module PennylaneClient
  module Resources
    # SEPA mandates: `client.sepa_mandates`.
    #
    # Attributes go to Pennylane as given, keyword for keyword, through the
    # Encoder. Responses are deep-frozen Hashes.
    class SepaMandates < Resource
      # Every SEPA mandate, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page.
      #
      #   sepa_mandates.list(filter: [{ field: "customer_id", operator: "eq", value: "7" }])
      def list(**params) = paginate(:getSepaMandates, **params)

      # One SEPA mandate.
      def find(id) = call(:getSepaMandate, id:)

      # Creates a SEPA mandate for a customer. Pennylane requires
      # `customer_id:`, `iban:`, `bic:`, `identifier:` and `signed_at:`.
      def create(**attributes) = call(:postSepaMandates, **attributes)

      # Updates a SEPA mandate. Only the attributes you pass change.
      def update(id, **attributes) = call(:putSepaMandate, id:, **attributes)

      # Deletes a SEPA mandate. Returns true.
      def delete(id) = call(:deleteSepaMandate, id:)
    end
  end
end
