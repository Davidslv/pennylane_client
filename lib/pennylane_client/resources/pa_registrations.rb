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
      # cursor here, so this is one request and returns its items. If
      # Pennylane ever answers `has_more: true`, the rest cannot be read,
      # so it raises Error rather than return part of the list.
      def list
        page = call(:getPaRegistrations)
        raise Error, "getPaRegistrations answered has_more: true, but takes no cursor" if page[:has_more]

        page.fetch(:items)
      end
    end
  end
end
