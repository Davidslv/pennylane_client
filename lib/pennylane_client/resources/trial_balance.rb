# frozen_string_literal: true

module PennylaneClient
  module Resources
    # The trial balance: `client.trial_balance`. Read-only.
    class TrialBalance < Resource
      # The trial balance for a period, one Hash per ledger account
      # (`number`, `formatted_number`, `label`, `debits`, `credits`, amounts
      # as Strings), as an Enumerator::Lazy, up to 1000 a page. The period
      # is required; a Date is sent as "2026-01-01". `is_auxiliary: true`
      # includes the auxiliary accounts. No `filter:` or `sort:`.
      #
      #   trial_balance.list(period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 12, 31))
      def list(period_start:, period_end:, **params)
        paginate(:getTrialBalance, period_start:, period_end:, **params)
      end
    end
  end
end
