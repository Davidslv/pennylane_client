# frozen_string_literal: true

require "uri"

module PennylaneClient
  module Middleware
    # Sends a call again when that is safe (proposal 0001, D5):
    #
    # - 429, for any verb, after `retry-after` seconds. A 429 means Pennylane
    #   did not run the request.
    # - 500, 502, 503, 504, ConnectionError and TimeoutError, for GET only.
    #   A POST, PUT or DELETE may have been applied, and Pennylane does not
    #   deduplicate writes. `retry: :always` on a call opts in.
    #
    # At most 3 attempts. Waits are exponential with full jitter (a random
    # time between 0 and 0.5 s, then 1 s), and all waits in one call stay
    # under 30 s: a wait that would pass the cap, such as a long
    # `retry-after`, is not taken and the last answer stands.
    #
    # Each retry emits a `type: :retry` event. Retry sits outside RateLimit,
    # so every attempt takes its own call from the bucket.
    #
    # @api private
    class Retry
      RETRY_STATUSES = [500, 502, 503, 504].freeze
      NO_RESPONSE = [ConnectionError, TimeoutError].freeze

      def initialize(app, instrumentation, max_attempts: 3, base_delay: 0.5, max_wait: 30.0,
                     sleeper: ->(seconds) { sleep(seconds) }, random: Random.new)
        @app = app
        @instrumentation = instrumentation
        @max_attempts = max_attempts
        @base_delay = base_delay
        @max_wait = max_wait
        @sleeper = sleeper
        @random = random
      end

      def call(request)
        waited = 0.0
        (1..).each do |attempt|
          response, error = send_once(request)
          wait = delay(request, response, error, attempt) if attempt < @max_attempts
          return finish(response, error) unless wait && waited + wait <= @max_wait

          report(request, attempt + 1, wait, response, error)
          @sleeper.call(wait)
          waited += wait
        end
      end

      private

      def send_once(request)
        [@app.call(request), nil]
      rescue *NO_RESPONSE => e
        [nil, e]
      end

      def finish(response, error)
        raise error if error

        response
      end

      def delay(request, response, error, attempt)
        if response&.status == 429
          retry_after(response) || backoff(attempt)
        elsif (error || RETRY_STATUSES.include?(response&.status)) && repeatable?(request)
          backoff(attempt)
        end
      end

      def repeatable?(request) = request.verb == :get || request.retry_policy == :always

      def backoff(attempt) = @random.rand * @base_delay * (2**(attempt - 1))

      def retry_after(response)
        seconds = Float(response.headers["retry-after"], exception: false)
        seconds&.clamp(0.0, nil)
      end

      def report(request, attempt, wait, response, error)
        @instrumentation.record({ type: :retry, operation_id: request.operation_id, method: request.verb.to_s.upcase,
                                  path: URI(request.url).path, attempt:, wait: wait.round(3),
                                  status: response&.status, error: error&.class&.name }.freeze)
      end
    end
  end
end
