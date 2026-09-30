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
  #   unless the caller passes `body:` explicitly (six Operations take a
  #   JSON array, which keyword params cannot build);
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
    def explicit_body(operation, rest, body)
      return body if rest.empty?

      raise ArgumentError,
            "unexpected parameters #{rest.keys.inspect} for #{operation.id.inspect} with an explicit body"
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

        URI.encode_uri_component(Encoder.encode(params.delete(name)).to_s)
      end
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

    def handle(response)
      raise Error.from_response(response) unless response.success?
      return true if response.body.to_s.strip.empty?

      JSON.parse(response.body, symbolize_names: true, freeze: true)
    rescue JSON::ParserError
      raise Error.new("#{response.status}: the response body is not JSON", status: response.status,
                                                                           body: response.body,
                                                                           headers: response.headers)
    end
  end
end
