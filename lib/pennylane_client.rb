# frozen_string_literal: true

require_relative "pennylane_client/version"
require_relative "pennylane_client/operation"
require_relative "pennylane_client/operations"
require_relative "pennylane_client/response"
require_relative "pennylane_client/errors"
require_relative "pennylane_client/encoder"
require_relative "pennylane_client/multipart"
require_relative "pennylane_client/registry"
require_relative "pennylane_client/request"
require_relative "pennylane_client/net_http_transport"
require_relative "pennylane_client/instrumentation"
require_relative "pennylane_client/limiter"
require_relative "pennylane_client/limiter_registry"
require_relative "pennylane_client/middleware/instrument"
require_relative "pennylane_client/middleware/rate_limit"
require_relative "pennylane_client/middleware/retry"
require_relative "pennylane_client/middleware/auth"
require_relative "pennylane_client/executor"
require_relative "pennylane_client/paginator"
require_relative "pennylane_client/configuration"
require_relative "pennylane_client/resources/resource"
require_relative "pennylane_client/resources/customer_invoices"
require_relative "pennylane_client/resources/customers"
require_relative "pennylane_client/resources/supplier_invoices"
require_relative "pennylane_client/resources/suppliers"
require_relative "pennylane_client/client"

# Unofficial Ruby client for the Pennylane Company API v2.
# Not affiliated with Pennylane.
module PennylaneClient
  # Shortcut for PennylaneClient::Client.new.
  def self.new(...)
    Client.new(...)
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield configuration
  end
end
