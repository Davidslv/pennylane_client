# frozen_string_literal: true

module PennylaneClient
  # The entry point. Wiring only: it composes the middleware around the
  # Transport and hands calls to the Executor.
  #
  #   client = PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"))
  #   client.call(:getCustomerInvoice, id: 42)
  #
  # `token` is a String, or anything responding to `#call` that returns the
  # current token (Middleware::Auth). `logger` and `on_request` default to
  # PennylaneClient.configuration. `transport` and `base_url` are there for
  # tests and fakes.
  class Client
    DEFAULT_BASE_URL = "https://app.pennylane.com"

    def initialize(token:, base_url: DEFAULT_BASE_URL, transport: NetHttpTransport.default,
                   logger: PennylaneClient.configuration.logger,
                   on_request: PennylaneClient.configuration.on_request)
      @base_url = base_url
      instrumentation = Instrumentation.new(logger:, on_request:)
      pipeline = Middleware::Auth.new(Middleware::Instrument.new(transport, instrumentation), token)
      @executor = Executor.new(registry: Registry.default, transport: pipeline, base_url:)
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
