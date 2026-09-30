# frozen_string_literal: true

module PennylaneClient
  # What the Executor hands a Transport: a lower-case verb Symbol, the full
  # URL String, the headers, and the encoded body String (nil for none).
  #
  # The headers carry the token, so every way of printing a Request
  # filters the Authorization header.
  Request = Data.define(:verb, :url, :headers, :body) do
    def inspect
      shown = headers.to_h { |name, value| [name, name.casecmp?("authorization") ? "[FILTERED]" : value] }
      "#<data #{self.class} verb=#{verb.inspect}, url=#{url.inspect}, headers=#{shown.inspect}, body=#{body.inspect}>"
    end
    alias_method :to_s, :inspect

    def pretty_print(printer) = printer.text(inspect)
  end
end
