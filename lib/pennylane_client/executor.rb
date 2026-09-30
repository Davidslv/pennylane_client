# frozen_string_literal: true

require "json"
require "uri"

module PennylaneClient
  # Runs one Operation: builds the Request, sends it through the Transport,
  # and turns the Response into a return value or an Error.
  #
  # Parameters are split by where the Operation wants them:
  #
  # - names in the path template (`{id}`) fill the path, escaped;
  # - when the Operation takes a JSON body, everything else is the body,
  #   unless the caller passes the body as the third argument of #call
  #   (Client#call's second). Six Operations take a JSON array, which keyword
  #   params cannot build. A `body:` keyword is an ordinary param: it is sent
  #   as a field named "body";
  # - when the Operation takes a multipart body, everything else is a form
  #   field, and files stream from disk (Multipart). Files the Executor
  #   opened are closed once the call is over;
  # - otherwise everything else is the query. Structured query values
  #   (Pennylane's `filter` is a JSON array) are sent as JSON strings.
  #
  # No Operation in the contract snapshot takes both a body and a query.
  #
  # The transport is usually the middleware pipeline Client composes.
  class Executor
    PATH_PARAMETER = /\{(\w+)\}/
    DOT_SEGMENTS = %w[. ..].freeze

    def initialize(registry:, transport:, base_url:)
      @registry = registry
      @transport = transport
      @base_url = base_url
    end

    def call(operation_id, params = {}, body = nil, retry_policy: :default)
      operation = @registry.fetch(operation_id)
      request = build(operation, params, body).with(retry_policy:)
      handle(@transport.call(request))
    ensure
      request.body.close if request&.body.respond_to?(:close)
    end

    def inspect = "#<#{self.class.name} base_url=#{@base_url.inspect}>"

    private

    def build(operation, params, body)
      rest = params.dup
      url = @base_url + fill_path(operation, rest)

      case operation.body
      when :json then json_request(operation, url, body.nil? ? rest : explicit_body(operation, rest, body))
      when :multipart then multipart_request(operation, url, rest, body)
      else query_request(operation, url, rest, body)
      end
    end

    # Every param left after the path is one form field; files stream.
    def multipart_request(operation, url, params, body)
      raise ArgumentError, "#{operation.id.inspect} takes its form fields as keywords" unless body.nil?

      form = Multipart.new(params)
      form_headers = headers.merge("Content-Type" => form.content_type, "Content-Length" => form.size.to_s)
      Request.new(verb: operation.verb, url:, headers: form_headers, body: form, operation_id: operation.id)
    end

    def query_request(operation, url, params, body)
      raise ArgumentError, "#{operation.id.inspect} takes no request body" unless body.nil?

      Request.new(verb: operation.verb, url: url + query(params), headers:, body: nil, operation_id: operation.id)
    end

    # A body passed as is, for the Operations whose body is a JSON array.
    # Every other param must have been a path parameter.
    # A Hash body may not name a path parameter too: which id was meant?
    def explicit_body(operation, rest, body)
      unless rest.empty?
        raise ArgumentError,
              "unexpected parameters #{rest.keys.inspect} for #{operation.id.inspect} with an explicit body"
      end
      refuse_path_keys(operation, body) if body.is_a?(Hash)
      body
    end

    def refuse_path_keys(operation, body)
      names = operation.path.scan(PATH_PARAMETER).flatten
      clashes = body.keys.select { names.include?(_1.to_s) }
      return if clashes.empty?

      raise ArgumentError,
            "the body names the path parameter #{clashes.inspect} of #{operation.id.inspect}; pass it only as a keyword"
    end

    def json_request(operation, url, params)
      Request.new(verb: operation.verb, url:, headers: headers(json: true), body: JSON.generate(Encoder.encode(params)),
                  operation_id: operation.id)
    end

    def fill_path(operation, params)
      operation.path.gsub(PATH_PARAMETER) do
        name = Regexp.last_match(1).to_sym
        unless params.key?(name)
          raise ArgumentError, "missing path parameter #{name.inspect} for #{operation.id.inspect}"
        end

        path_segment(operation, name, params.delete(name))
      end
    end

    # One escaped path segment. An empty value would leave an empty segment
    # (GET /customer_invoices/ is the list), and "." or ".." a dot segment
    # that a server may resolve to another Operation, so both are refused.
    def path_segment(operation, name, value)
      text = Encoder.encode(value).to_s
      raise ArgumentError, "path parameter #{name.inspect} for #{operation.id.inspect} is empty" if text.empty?
      if DOT_SEGMENTS.include?(text)
        raise ArgumentError, "path parameter #{name.inspect} for #{operation.id.inspect} cannot be #{text.inspect}"
      end

      URI.encode_uri_component(text)
    end

    def query(params)
      pairs = params.compact.map { |name, value| [name.to_s, query_value(value)] }
      pairs.empty? ? "" : "?#{URI.encode_www_form(pairs)}"
    end

    def query_value(value)
      encoded = Encoder.encode(value)
      encoded.is_a?(Hash) || encoded.is_a?(Array) ? JSON.generate(encoded) : encoded.to_s
    end

    def headers(json: false)
      headers = { "Accept" => "application/json", "User-Agent" => "pennylane_client/#{VERSION} (ruby #{RUBY_VERSION})" }
      headers["Content-Type"] = "application/json" if json
      headers
    end

    # A 2xx body that is not valid UTF-8 raises Error, as a body that is not
    # JSON does (JSON is UTF-8, RFC 8259). It is not scrubbed: a record read
    # with U+FFFD in place of its bytes could be written back that way.
    def handle(response)
      raise Error.from_response(response) unless response.success?

      body = response.body.to_s
      raise unreadable(response, "is not valid UTF-8") unless body.valid_encoding?
      return true if body.strip.empty?

      JSON.parse(body, symbolize_names: true, freeze: true)
    rescue JSON::ParserError
      raise unreadable(response, "is not JSON")
    end

    def unreadable(response, reason)
      Error.new("#{response.status}: the response body #{reason}",
                status: response.status, body: response.body, headers: response.headers)
    end
  end
end
