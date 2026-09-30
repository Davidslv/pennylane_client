# frozen_string_literal: true

module PennylaneClient
  # One Operation from the contract snapshot: an HTTP method on a path.
  #
  # - id: the operationId, as a Symbol (e.g. :getCustomerInvoices)
  # - verb: the HTTP method, lower-case Symbol (:get, :post, :put, :delete)
  # - path: the full path template, e.g. "/api/external/v2/journals/{id}"
  # - paginated: true when the operation takes a cursor
  # - max_limit: the largest `limit` a paginated operation accepts (100 or
  #   1000), nil when it is not paginated
  # - body: :json, :multipart, or nil when it takes no request body
  # - success: the documented 2xx status code
  # - deprecated: true when Pennylane marks the operation deprecated
  #
  # @api private
  Operation = Data.define(:id, :verb, :path, :paginated, :max_limit, :body, :success, :deprecated)
end
