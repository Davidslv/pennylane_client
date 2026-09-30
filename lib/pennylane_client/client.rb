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
  # PennylaneClient.configuration. `limiters` defaults to the process-wide
  # LimiterRegistry, so every Client on one token shares one budget.
  # `max_retry_wait` caps the seconds one call spends waiting between
  # retries (Middleware::Retry). `transport` and `base_url` are there for
  # tests and fakes.
  #
  # Each call runs through the middleware, outermost first:
  #
  #   Auth -> Retry -> RateLimit -> Instrument -> Transport
  class Client
    DEFAULT_BASE_URL = "https://app.pennylane.com"
    RETRY_POLICIES = { nil => :default, always: :always }.freeze

    def initialize(token:, base_url: DEFAULT_BASE_URL, transport: NetHttpTransport.default,
                   logger: PennylaneClient.configuration.logger,
                   on_request: PennylaneClient.configuration.on_request,
                   limiters: LimiterRegistry.default, max_retry_wait: 30.0)
      @base_url = base_url
      instrumentation = Instrumentation.new(logger:, on_request:)
      pipeline = Middleware::Instrument.new(transport, instrumentation)
      pipeline = Middleware::RateLimit.new(pipeline, limiters, instrumentation)
      pipeline = Middleware::Retry.new(pipeline, instrumentation, max_wait: max_retry_wait)
      pipeline = Middleware::Auth.new(pipeline, token)
      @executor = Executor.new(registry: Registry.default, transport: pipeline, base_url:)
    end

    # Runs any Registered operation by its Pennylane operationId.
    # Returns a deep-frozen Hash with symbol keys, or true for an empty 2xx.
    #
    # Keyword params fill the path, then the JSON body or the query. Pass the
    # body positionally when it is not an object, e.g. an array:
    #
    #   client.call(:putCustomerCategories, [{ id: 1, weight: "1" }], customer_id: 9)
    #
    # `retry: :always` lets a POST, PUT or DELETE be retried after a 5xx or
    # no response, for a call the caller knows is safe to repeat. It is not
    # sent to Pennylane.
    def call(operation_id, body = nil, **params)
      retry_policy = RETRY_POLICIES.fetch(params.delete(:retry)) do |given|
        raise ArgumentError, "retry must be :always, got #{given.inspect}"
      end
      @executor.call(operation_id, params, body, retry_policy:)
    end

    # Every item of a list operation, as an Enumerator::Lazy of Hashes. It
    # follows `next_cursor` as far as the caller reads and sends `filter`
    # and `sort` again on every page (Paginator):
    #
    #   client.paginate(:getCustomerInvoices, filter: [{ field: "status", operator: "eq", value: "draft" }])
    #         .each { |invoice| puts invoice[:invoice_number] }
    def paginate(operation_id, **params) = paginator(operation_id, params).items

    # The same walk as `paginate`, one Hash per page (`items`, `has_more`,
    # `next_cursor`).
    def pages(operation_id, **params) = paginator(operation_id, params).pages

    # The named Customer Invoices operations (Resources::CustomerInvoices).
    def customer_invoices = @customer_invoices ||= Resources::CustomerInvoices.new(self)

    # The named Customers operations, company and individual
    # (Resources::Customers).
    def customers = @customers ||= Resources::Customers.new(self)

    # The named Supplier Invoices operations (Resources::SupplierInvoices).
    def supplier_invoices = @supplier_invoices ||= Resources::SupplierInvoices.new(self)

    # The named Suppliers operations (Resources::Suppliers).
    def suppliers = @suppliers ||= Resources::Suppliers.new(self)

    # The named SEPA mandate operations (Resources::SepaMandates).
    def sepa_mandates = @sepa_mandates ||= Resources::SepaMandates.new(self)

    # The named GoCardless mandate operations (Resources::GocardlessMandates).
    def gocardless_mandates = @gocardless_mandates ||= Resources::GocardlessMandates.new(self)

    # The named Pro Account mandate operations (Resources::ProAccountMandates).
    def pro_account_mandates = @pro_account_mandates ||= Resources::ProAccountMandates.new(self)

    # The named Bank accounts operations (Resources::BankAccounts).
    def bank_accounts = @bank_accounts ||= Resources::BankAccounts.new(self)

    # The named Bank Establishments operations (Resources::BankEstablishments).
    def bank_establishments = @bank_establishments ||= Resources::BankEstablishments.new(self)

    # The named Transactions operations (Resources::Transactions).
    def transactions = @transactions ||= Resources::Transactions.new(self)

    # The named Quotes operations (Resources::Quotes).
    def quotes = @quotes ||= Resources::Quotes.new(self)

    # The named Commercial Documents operations: proformas, shipping orders
    # and purchasing orders (Resources::CommercialDocuments).
    def commercial_documents = @commercial_documents ||= Resources::CommercialDocuments.new(self)

    def inspect = "#<#{self.class.name} base_url=#{@base_url.inspect}>"

    private

    # A list is a GET, which Retry already retries; `retry` would otherwise
    # be sent to Pennylane as a query param.
    def paginator(operation_id, params)
      raise ArgumentError, "paginate takes no retry policy: a GET is retried already" if params.key?(:retry)

      Paginator.new(executor: @executor, operation: Registry.default.fetch(operation_id), params:)
    end
  end
end
