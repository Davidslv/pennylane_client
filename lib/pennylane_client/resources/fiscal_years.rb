# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Fiscal years: `client.fiscal_years`. Read-only.
    class FiscalYears < Resource
      # Every fiscal year of the company, as an Enumerator::Lazy of Hashes,
      # newest id first unless you pass `sort:` (`id` or `start`). No
      # `filter:`.
      #
      #   fiscal_years.list(sort: "-start").first
      def list(**params) = paginate(:"company-fiscal-years", **params)
    end
  end
end
