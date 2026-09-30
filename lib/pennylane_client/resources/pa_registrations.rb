# frozen_string_literal: true

module PennylaneClient
  module Resources
    # PA registrations: `client.pa_registrations`, the company's
    # registrations with a Plateforme Agréée for e-invoicing.
    class PaRegistrations < Resource
      # Every PA registration, as a frozen Array of Hashes. Use it to check
      # whether the company has finished PA onboarding: look for
      # `status: "activated"` and the `exchange_direction` you need. A
      # registration with a nil `siret` is the SIREN (head office); the
      # others are establishments.
      #
      # Pennylane answers with `has_more` and `next_cursor` but takes no
      # cursor here, so this is one request and returns its items.
      def list = call(:getPaRegistrations).fetch(:items)
    end
  end
end
