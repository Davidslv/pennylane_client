# frozen_string_literal: true

module PennylaneClient
  # Which fiber owns which connections, for NetHttpTransport, so the
  # connections of fibers that have finished can be closed. Fibers are held
  # weakly: a fiber collected by GC takes its entry with it. The lock is
  # taken when a fiber first connects and when a new connection is opened,
  # never for a call on an open connection.
  #
  # @api private
  class ConnectionOwners
    def initialize
      @owners = ObjectSpace::WeakMap.new
      @lock = Mutex.new
    end

    # Records the current fiber's connections and returns them.
    def register(connections)
      @lock.synchronize { @owners[Fiber.current] = connections }
    end

    # Removes and returns the connections of every fiber that has finished.
    # A finished fiber never runs again, so no call is using them.
    def finished
      @lock.synchronize do
        fibers = []
        @owners.each_key { fibers << _1 unless _1.alive? }
        fibers.map { @owners.delete(_1) }
      end
    end

    def inspect = "#<#{self.class.name}>"
  end
end
