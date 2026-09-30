# frozen_string_literal: true

module PennylaneClient
  # One Operation from the contract snapshot: an HTTP method on a path.
  #
  # - id: the operationId, as a Symbol (e.g. :getCustomerInvoices)
  # - verb: the HTTP method, lower-case Symbol (:get, :post, :put, :delete)
  # - path: the full path template, e.g. "/api/external/v2/journals/{id}"
  # - paginated: true when the operation takes a cursor
  # - body: :json, :multipart, or nil when it takes no request body
  # - success: the documented 2xx status code
  # - deprecated: true when Pennylane marks the operation deprecated
  Operation = Data.define(:id, :verb, :path, :paginated, :body, :success, :deprecated)
end
