# frozen_string_literal: true

module PennylaneClient
  # Where request events go: one log line and one `on_request` call each.
  #
  # An event is a frozen Hash with plain values only:
  #
  #   { operation_id: :getMe, method: "GET", path: "/api/external/v2/me",
  #     status: 200, error: nil, duration: 12.3 }
  #
  # `status` is nil and `error` names the Error class when no response
  # arrived. `duration` is in milliseconds. The path never has a query, and
  # nothing in an event comes from the request headers, so the token
  # cannot appear.
  class Instrumentation
    def initialize(logger: nil, on_request: nil)
      @logger = logger
      @on_request = on_request
    end

    # Never raises. A failing logger or callback must not turn a request
    # that reached Pennylane into an error the caller might retry.
    def record(event)
      guard { log(event) } if @logger
      guard("on_request failed: ") { @on_request.call(event) } if @on_request
    end

    private

    def guard(prefix = "")
      yield
    rescue StandardError => e
      report_failure("pennylane_client #{prefix}#{e.class}: #{e.message}")
    end

    def report_failure(line)
      @logger ? @logger.warn(line) : Kernel.warn(line)
    rescue StandardError
      Kernel.warn(line)
    end

    def log(event)
      line = "pennylane_client #{event[:operation_id]} #{event[:method]} #{event[:path]}"
      if event[:error]
        @logger.warn("#{line} failed: #{event[:error]} (#{event[:duration]} ms)")
      else
        @logger.info("#{line} -> #{event[:status]} (#{event[:duration]} ms)")
      end
    end
  end
end
