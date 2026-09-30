# frozen_string_literal: true

module PennylaneClient
  # What the Executor hands the middleware and then a Transport: a
  # lower-case verb Symbol, the full URL String, the headers, and the
  # encoded body: a String, a Multipart for an upload (it reads like an IO:
  # `read`, `rewind`, `size`), or nil for none.
  #
  # `operation_id` names the Operation for events. `retry_policy` is
  # `:default`, or `:always` when the caller passed `retry: :always`.
  #
  # The headers carry the token once Auth has run, so every way of printing
  # a Request filters the Authorization header.
  Request = Data.define(:verb, :url, :headers, :body, :operation_id, :retry_policy) do
    def initialize(operation_id: nil, retry_policy: :default, **) = super

    def inspect
      shown = headers.to_h { |name, value| [name, name.casecmp?("authorization") ? "[FILTERED]" : value] }
      "#<data #{self.class} verb=#{verb.inspect}, url=#{url.inspect}, headers=#{shown.inspect}, body=#{body.inspect}>"
    end
    alias_method :to_s, :inspect

    def pretty_print(printer) = printer.text(inspect)
  end
end
