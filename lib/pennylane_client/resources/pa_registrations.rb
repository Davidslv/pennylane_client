# frozen_string_literal: true

module PennylaneClient
  module Resources
    # PA registrations: `client.pa_registrations`, the company's
    # registrations with a Plateforme Agréée for e-invoicing.
    class PaRegistrations < Resource
      # Every PA registration, as an Enumerator::Lazy of Hashes, like every
      # other list. Use it to check whether the company has finished PA
      # onboarding: look for `status: "activated"` and the
      # `exchange_direction` you need. A registration with a nil `siret` is
      # the SIREN (head office); the others are establishments.
      #
      # Pennylane answers with `has_more` and `next_cursor` but takes no
      # cursor here, so reading it is one request. If Pennylane ever answers
      # `has_more: true`, the rest cannot be read, so reading raises Error
      # rather than return part of the list.
      def list(**params) = paginate(:getPaRegistrations, **params)
    end
  end
end
