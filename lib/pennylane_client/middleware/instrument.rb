# frozen_string_literal: true

require "uri"

module PennylaneClient
  # Middleware wraps the Transport. Each one is `call(request) -> Response`
  # around the next, so each policy has one class. Client composes them:
  #
  #   Auth -> Retry -> RateLimit -> Instrument -> Transport
  #
  # @api private
  module Middleware
    # Records every attempt that reaches the Transport, answered or not, as
    # one `type: :request` event. It sits next to the Transport, so a retried
    # call records each attempt and `duration` never includes a wait.
    #
    # @api private
    class Instrument
      def initialize(app, instrumentation)
        @app = app
        @instrumentation = instrumentation
      end

      def call(request)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = @app.call(request)
        report(request, started, status: response.status)
        response
      rescue Error => e
        report(request, started, error: e.class.name)
        raise
      end

      private

      def report(request, started, status: nil, error: nil)
        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
        @instrumentation.record({ type: :request, operation_id: request.operation_id,
                                  method: request.verb.to_s.upcase, path: URI(request.url).path,
                                  status:, error:, duration: }.freeze)
      end
    end
  end
end
