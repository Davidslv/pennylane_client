# frozen_string_literal: true

module PennylaneClient
  module Middleware
    # Adds `Authorization: Bearer <token>`. The token is a String, or a token
    # provider: anything responding to `#call` that returns the current
    # token, asked once per call. The client never refreshes a token itself
    # (D7).
    #
    # A token with whitespace or a line break is refused without echoing it,
    # because Net::HTTP would otherwise raise an error quoting the header.
    class Auth
      FORMAT = /\A[[:graph:]]+\z/

      def initialize(app, token)
        unless token.respond_to?(:call) || valid?(token)
          raise ArgumentError, "token must be a non-empty String with no spaces or line breaks, " \
                               "or respond to #call"
        end

        @app = app
        @token = token
      end

      def call(request)
        @app.call(request.with(headers: request.headers.merge("Authorization" => "Bearer #{current_token}")))
      end

      def inspect = "#<#{self.class.name}>"

      def pretty_print(printer) = printer.text(inspect)

      private

      def current_token
        return @token unless @token.respond_to?(:call)

        token = @token.call
        return token if valid?(token)

        raise ArgumentError, "the token provider returned a token that is not a non-empty String " \
                             "with no spaces or line breaks"
      end

      def valid?(token) = token.is_a?(String) && token.match?(FORMAT)
    end
  end
end
