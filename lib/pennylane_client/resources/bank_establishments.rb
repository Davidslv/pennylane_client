# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Bank establishments, the banks Pennylane knows:
    # `client.bank_establishments`. Read only. A bank account's
    # `bank_establishment_id:` is one of these ids.
    class BankEstablishments < Resource
      # Every bank establishment, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page. The filter takes `id` only.
      def list(**params) = paginate(:getBankEstablishments, **params)
    end
  end
end
