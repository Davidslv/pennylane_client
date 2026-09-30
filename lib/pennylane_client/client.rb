# frozen_string_literal: true

module PennylaneClient
  # The entry point. Wiring only: it builds the Executor and hands calls to it.
  #
  #   client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))
  #   client.call(:getCustomerInvoice, id: 42)
  #
  # `logger` and `on_request` default to PennylaneClient.configuration.
  # `transport` and `base_url` are there for tests and fakes.
  class Client
    DEFAULT_BASE_URL = "https://app.pennylane.com"

    def initialize(token:, base_url: DEFAULT_BASE_URL, transport: NetHttpTransport.default,
                   logger: PennylaneClient.configuration.logger,
                   on_request: PennylaneClient.configuration.on_request)
      unless token.is_a?(String) && token.match?(/\A[[:graph:]]+\z/)
        raise ArgumentError, "token must be a non-empty String with no spaces or line breaks"
      end

      @base_url = base_url
      instrumentation = Instrumentation.new(logger:, on_request:)
      pipeline = Middleware::Instrument.new(transport, instrumentation)
      @executor = Executor.new(registry: Registry.default, transport: pipeline, token:, base_url:)
    end

    # Runs any Registered operation by its Pennylane operationId.
    # Returns a deep-frozen Hash with symbol keys, or true for an empty 2xx.
    #
    # Keyword params fill the path, then the JSON body or the query. Pass the
    # body positionally when it is not an object, e.g. an array:
    #
    #   client.call(:putCustomerCategories, [{ id: 1, weight: "1" }], customer_id: 9)
    def call(operation_id, body = nil, **params)
      @executor.call(operation_id, params, body)
    end

    def inspect = "#<#{self.class.name} base_url=#{@base_url.inspect}>"
  end
end
