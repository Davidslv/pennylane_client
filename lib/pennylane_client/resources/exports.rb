# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Exports: `client.exports`, the FEC, the General Ledger and the
    # Analytical General Ledger for a period.
    #
    # Pennylane builds an export in the background. `create_*` asks for one
    # and returns it `pending`; `find_*` reads its `status` (`pending`,
    # `ready` or `error`) and, once ready, its `file_url`. The URL expires
    # 30 minutes after it is issued.
    #
    # `generate_*` does both: it creates the export, then reads it every
    # `interval` seconds until it is ready, and returns it. It raises
    # ExportError when the export fails or is still not ready after
    # `timeout` seconds; the error's `export` has the id to poll later.
    #
    #   export = client.exports.generate_fec(period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 6, 30))
    #   download(export[:file_url])
    class Exports < Resource
      def initialize(client, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                     sleeper: ->(seconds) { sleep(seconds) })
        super(client)
        @clock = clock
        @sleeper = sleeper
      end

      # Asks for a FEC export. Pennylane requires `period_start:` and
      # `period_end:`.
      def create_fec(retry: nil, **attributes) = call(:exportFec, retry:, **attributes)

      # One FEC export.
      def find_fec(id) = call(:getFecExport, id:)

      # Creates a FEC export and waits until it is ready.
      def generate_fec(timeout: 300, interval: 5, retry: nil, **attributes)
        generate(:exportFec, :getFecExport, attributes, timeout:, interval:, retry:)
      end

      # Asks for a General Ledger export, an xlsx file. Pennylane requires
      # `period_start:` and `period_end:`.
      def create_general_ledger(retry: nil, **attributes) = call(:exportGeneralLedger, retry:, **attributes)

      # One General Ledger export.
      def find_general_ledger(id) = call(:getGeneralLedgerExport, id:)

      # Creates a General Ledger export and waits until it is ready.
      def generate_general_ledger(timeout: 300, interval: 5, retry: nil, **attributes)
        generate(:exportGeneralLedger, :getGeneralLedgerExport, attributes, timeout:, interval:, retry:)
      end

      # Asks for an Analytical General Ledger export, an xlsx file.
      # Pennylane requires `period_start:` and `period_end:`; `mode:` is
      # "in_line" (the default) or "in_column".
      def create_analytical_general_ledger(retry: nil, **attributes)
        call(:exportAnalyticalGeneralLedger, retry:, **attributes)
      end

      # One Analytical General Ledger export.
      def find_analytical_general_ledger(id) = call(:getAnalyticalGeneralLedgerExport, id:)

      # Creates an Analytical General Ledger export and waits until it is
      # ready.
      def generate_analytical_general_ledger(timeout: 300, interval: 5, retry: nil, **attributes)
        generate(:exportAnalyticalGeneralLedger, :getAnalyticalGeneralLedgerExport, attributes,
                 timeout:, interval:, retry:)
      end

      private

      # Reads the export straight after creating it: only a read carries
      # `file_url`. Then once per `interval` while it is pending. `retry`
      # applies to the create; the reads are GETs, retried already.
      def generate(create_id, find_id, attributes, timeout:, interval:, retry:)
        raise ArgumentError, "interval must be positive, got #{interval.inspect}" unless interval.positive?

        deadline = @clock.call + timeout
        id = call(create_id, retry:, **attributes).fetch(:id)
        loop do
          export = call(find_id, id:)
          return export if ready?(export)
          raise ExportError.new("export #{id} not ready in #{timeout} s", export:) if @clock.call + interval > deadline

          @sleeper.call(interval)
        end
      end

      # True once ready; raises once failed.
      def ready?(export)
        raise ExportError.new("export #{export[:id]} failed", export:) if export[:status] == "error"

        export[:status] == "ready"
      end
    end
  end
end
