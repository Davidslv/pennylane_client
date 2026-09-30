# frozen_string_literal: true

module PennylaneClient
  # Named operations, one class per resource group. Each public method is a
  # hand-written one-liner over the Client, so the Ruby name is a promise
  # that survives Pennylane renaming an operationId (proposal 0001, D3).
  module Resources
    # Holds the Client and gives subclasses `call` and `paginate`. No state
    # and no logic of its own.
    class Resource
      def initialize(client)
        @client = client
      end

      def inspect = "#<#{self.class.name}>"

      private

      def call(...) = @client.call(...)
      def paginate(...) = @client.paginate(...)
    end
  end
end
