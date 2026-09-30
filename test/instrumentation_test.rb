# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"

class InstrumentationTest < Minitest::Test
  EVENT = { operation_id: :postJournals, method: "POST", path: "/api/external/v2/journals", status: 201,
            error: nil, duration: 1.0 }.freeze

  # A write that reached Pennylane must not look failed to the caller, or
  # the caller may send it again.
  def test_a_failing_callback_is_logged_not_raised
    log = StringIO.new
    instrumentation = PennylaneClient::Instrumentation.new(logger: Logger.new(log), on_request: ->(_) { raise "boom" })

    instrumentation.record(EVENT)

    assert_includes log.string, "on_request failed: RuntimeError: boom"
  end

  def test_a_failing_logger_is_not_raised
    broken = Object.new
    def broken.info(*) = raise(IOError, "disk full")
    def broken.warn(*) = raise(IOError, "disk full")
    events = []

    _, stderr = capture_io do
      PennylaneClient::Instrumentation.new(logger: broken, on_request: events.method(:<<)).record(EVENT)
    end

    assert_equal [EVENT], events
    assert_includes stderr, "IOError: disk full"
  end

  def test_logs_a_rate_limit_wait
    log = StringIO.new
    PennylaneClient::Instrumentation.new(logger: Logger.new(log))
                                    .record({ type: :wait, operation_id: :getMe, method: "GET",
                                              path: "/api/external/v2/me", wait: 0.8 })

    assert_includes log.string, "pennylane_client getMe GET /api/external/v2/me waited 0.8 s for the rate limit"
  end
end
