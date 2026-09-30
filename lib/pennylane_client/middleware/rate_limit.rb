# frozen_string_literal: true

require "digest"
require "uri"

module PennylaneClient
  module Middleware
    # Keeps a token inside Pennylane's 25 requests per 5 seconds. Every
    # attempt takes a call from the token's Limiter first, waiting when the
    # bucket is empty, and every response's `ratelimit-remaining` and
    # `ratelimit-reset` headers correct the bucket, so another process
    # spending the same token is noticed.
    #
    # Limiters come from a LimiterRegistry, keyed by the SHA-256 of the
    # token so the token is never a key. A wait emits a `type: :wait` event.
    #
    # @api private
    class RateLimit
      def initialize(app, limiters, instrumentation)
        @app = app
        @limiters = limiters
        @instrumentation = instrumentation
      end

      def call(request)
        limiter = @limiters.fetch(key(request))
        waited = limiter.acquire
        report(request, waited) if waited.positive?

        response = @app.call(request)
        correct(limiter, response.headers)
        response
      end

      private

      # Auth, outside this middleware, has set the header as "Bearer <token>".
      def key(request)
        Digest::SHA256.hexdigest(request.headers.fetch("Authorization").delete_prefix("Bearer "))
      end

      def correct(limiter, headers)
        remaining = Integer(headers["ratelimit-remaining"], exception: false)
        return unless remaining

        limiter.update(remaining:, reset_at: Float(headers["ratelimit-reset"], exception: false))
      end

      def report(request, waited)
        @instrumentation.record({ type: :wait, operation_id: request.operation_id, method: request.verb.to_s.upcase,
                                  path: URI(request.url).path, wait: waited.round(3) }.freeze)
      end
    end
  end
end
