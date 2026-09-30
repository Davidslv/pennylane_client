# frozen_string_literal: true

require "json"

module PennylaneClient
  # Base class for everything the client raises about a request.
  #
  # Built from the response only, never from the request, so the token
  # cannot leak into a message. Pennylane uses several body shapes
  # (docs/api/contract/<date>/guides/errors.md); each is parsed defensively:
  #
  #   {"error": "unprocessable_entity", "message": "...", "details": {...}}
  #   {"status": 409, "error": "A document with ID ... already exists."}
  #   {"message": "..."}
  #   plain text, or nothing at all
  class Error < StandardError
    MESSAGE_LIMIT = 200

    # The HTTP status, or nil when no response arrived.
    attr_reader :status
    # The machine-readable `error` code when Pennylane sends one with a message.
    attr_reader :code
    # The `details` object, with symbol keys, when Pennylane sends one.
    attr_reader :details
    # The raw response body.
    attr_reader :body
    # The response headers, with lower-case names.
    attr_reader :headers

    def self.from_response(response)
      klass = STATUS_ERRORS.fetch(response.status) { response.status >= 500 ? ServerError : Error }
      klass.new(nil, status: response.status, body: response.body, headers: response.headers)
    end

    def initialize(message = nil, status: nil, body: nil, headers: {})
      @status = status
      @body = body
      @headers = headers
      parsed = parse(body)
      @code, text = describe(parsed)
      @details = parsed[:details] if parsed.is_a?(Hash)
      super(message || summary(text))
    end

    private

    def parse(body)
      return nil if body.nil? || body.strip.empty?

      JSON.parse(body, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    # Returns [code, text] for the message.
    def describe(parsed)
      return [nil, plain_text] unless parsed.is_a?(Hash)

      if parsed[:message].is_a?(String)
        [parsed[:error].is_a?(String) ? parsed[:error] : nil, parsed[:message]]
      elsif parsed[:error].is_a?(String)
        [nil, parsed[:error]]
      else
        [nil, plain_text]
      end
    end

    def plain_text
      text = body.to_s.strip
      text.empty? ? nil : text
    end

    # "422 unprocessable_entity: Entry lines are not balanced"
    def summary(text)
      text = "#{text[0, MESSAGE_LIMIT]}..." if text && text.length > MESSAGE_LIMIT
      [[status, code].compact.join(" "), text].reject { _1.nil? || _1.empty? }.join(": ")
    end
  end

  # 401: the token is missing, invalid or expired. The client never refreshes it.
  class AuthenticationError < Error; end
  # 403: the token is valid but lacks the scope.
  class PermissionError < Error; end
  # 404: the record does not exist or belongs to another company.
  class NotFoundError < Error; end
  # 409: the request conflicts with existing data, e.g. a duplicate import.
  class ConflictError < Error; end
  # 400 or 422: the payload is malformed or breaks a business rule. See #details.
  class ValidationError < Error; end
  # 5xx: a failure on Pennylane's side.
  class ServerError < Error; end
  # The connection failed before a response arrived.
  class ConnectionError < Error; end
  # The connection opened, or the request was sent, but no answer came in time.
  class TimeoutError < Error; end

  # 429: the rate limit was hit.
  class RateLimitError < Error
    # Seconds to wait, from the `retry-after` header, or nil when absent.
    def retry_after
      value = headers["retry-after"]
      Float(value) if value
    rescue ArgumentError
      nil
    end
  end

  # An export that failed, or was not ready in time (Resources::Exports).
  class ExportError < Error
    # The export as last read: its `id` and `status`.
    attr_reader :export

    def initialize(message, export:)
      @export = export
      super(message)
    end
  end

  # The documented statuses (errors guide). Any other 5xx is a ServerError;
  # anything else is the base Error.
  STATUS_ERRORS = {
    400 => ValidationError,
    401 => AuthenticationError,
    403 => PermissionError,
    404 => NotFoundError,
    409 => ConflictError,
    422 => ValidationError,
    429 => RateLimitError
  }.freeze
end
