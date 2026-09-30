# frozen_string_literal: true

module PennylaneClient
  # Named operations, one class per resource group. Each public method is a
  # hand-written one-liner over the Client, so the Ruby name is a promise
  # that survives Pennylane renaming an operationId (proposal 0001, D3).
  module Resources
    # Holds the Client and gives subclasses `call` and `paginate`, and
    # `call_on` and `paginate_on` for a method that takes the Operation's
    # path parameters positionally. No state of its own.
    class Resource
      def initialize(client)
        @client = client
      end

      def inspect = "#<#{self.class.name}>"

      private

      def call(...) = @client.call(...)
      def paginate(...) = @client.paginate(...)

      # `path` holds the path parameters, `params` the caller's keywords. A
      # keyword naming a path parameter raises: merged, it would replace the
      # positional id, and `update(1, id: 2)` would write record 2.
      def call_on(operation_id, path, **params)
        @client.call(operation_id, **path, **apart(operation_id, path, params))
      end

      def paginate_on(operation_id, path, **params)
        @client.paginate(operation_id, **path, **apart(operation_id, path, params))
      end

      def apart(operation_id, path, params)
        names = path.keys.map(&:to_s)
        clash = params.keys.find { names.include?(_1.to_s) }
        return params unless clash

        raise ArgumentError, "#{operation_id} takes #{clash} positionally; it cannot also be a keyword"
      end
    end
  end
end
