# frozen_string_literal: true

module PennylaneClient
  # Which fiber owns which connections, for NetHttpTransport, so the
  # connections of fibers that have finished can be closed. Fibers are held
  # weakly: a fiber collected by GC takes its entry with it. The lock is
  # taken when a fiber first connects and when a new connection is opened,
  # never for a call on an open connection.
  #
  # A forked child starts with no records. The parent's threads look
  # finished in the child, but their connections are the parent's sockets:
  # closing them would end the parent's TLS sessions, so they are forgotten.
  #
  # @api private
  class ConnectionOwners
    def initialize
      @owners = ObjectSpace::WeakMap.new
      @lock = Mutex.new
      @pid = Process.pid
    end

    # Records the current fiber's connections and returns them.
    def register(connections)
      @lock.synchronize { current[Fiber.current] = connections }
    end

    # Removes and returns the connections of every fiber that has finished.
    # A finished fiber never runs again, so no call is using them.
    def finished
      @lock.synchronize do
        fibers = []
        current.each_key { fibers << _1 unless _1.alive? }
        fibers.map { @owners.delete(_1) }
      end
    end

    def inspect = "#<#{self.class.name}>"

    private

    # This process's records. Called with the lock held.
    def current
      unless @pid == Process.pid
        @owners = ObjectSpace::WeakMap.new
        @pid = Process.pid
      end
      @owners
    end
  end
end
