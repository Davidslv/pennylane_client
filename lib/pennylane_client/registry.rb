# frozen_string_literal: true

module PennylaneClient
  # Raised when `call` is given an operationId the Registry does not hold.
  class UnknownOperationError < ArgumentError; end

  # A frozen lookup from operationId to Operation.
  class Registry
    def self.default
      DEFAULT
    end

    def initialize(operations)
      @operations = operations.to_h { [_1.id, _1] }.freeze
      freeze
    end

    def fetch(id)
      @operations.fetch(id.to_sym) { raise UnknownOperationError, "unknown operation #{id.to_sym.inspect}" }
    end

    def size = @operations.size

    DEFAULT = new(OPERATIONS)
  end
end
