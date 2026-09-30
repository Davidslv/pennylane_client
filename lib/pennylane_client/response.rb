# frozen_string_literal: true

module PennylaneClient
  # What a Transport returns: the status code, the headers with lower-case
  # names, and the raw body String ("" when there is none).
  Response = Data.define(:status, :headers, :body) do
    def success? = status.between?(200, 299)
  end
end
