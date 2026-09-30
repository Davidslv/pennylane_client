# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Company: `client.company`, the company behind the token.
    class Company < Resource
      # The gated features this company can use, as a Hash of feature name
      # to true or false. A feature is true only when every gate is open,
      # the billing plan included. Check it before sending a gated field:
      # with `installments: false`, a customer invoice sent with
      # installments either gets a 403 or is created with one installment.
      # Pennylane adds keys as it gates new features.
      #
      #   client.company.features[:installments]   # => true
      def features = call(:getCompanyFeatures)
    end
  end
end
