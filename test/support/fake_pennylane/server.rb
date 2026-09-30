# frozen_string_literal: true

require "socket"
require_relative "../fake_pennylane"

class FakePennylane
  # FakePennylane on a real socket: a small HTTP/1.1 server on 127.0.0.1
  # with keep-alive, one thread per connection. It lets a run use the real
  # NetHttpTransport, so keep-alive, timeouts, resets, streamed uploads and
  # several processes on one token are exercised for real.
  #
  #   server = FakePennylane::Server.new(FakePennylane.new).start
  #   PennylaneClient.new(token: "tok", base_url: server.url)
  #   server.stop
  #
  # A :hang keeps the connection silent for the fault's delay, then closes
  # it; a :reset closes it with a TCP reset. A request body is streamed to
  # the fake (Body), never held whole, and whatever the fake did not read is
  # drained before the next request on the connection.
  #
  # It counts connections: `connections_opened`, `open_connections` and
  # `peak_connections`, the most open at once.
  class Server
    attr_reader :port

    def initialize(fake)
      @fake = fake
      @lock = Mutex.new
      @connections = {}
      @opened = 0
      @peak = 0
    end

    def start
      @listener = TCPServer.new("127.0.0.1", 0)
      @port = @listener.addr[1]
      @acceptor = Thread.new { accept_loop }
      self
    end

    def url = "http://127.0.0.1:#{@port}"

    # Closes the listener and every connection, and waits for their threads.
    def stop
      @listener.close
      @acceptor.join
      @lock.synchronize { @connections.to_a }.each do |socket, thread|
        socket.close
        thread.join
      end
    end

    def connections_opened = @lock.synchronize { @opened }
    def open_connections = @lock.synchronize { @connections.size }
    def peak_connections = @lock.synchronize { @peak }

    # Whether every client has hung up, waiting up to `within` seconds.
    def idle?(within: 0)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + within
      sleep 0.01 until open_connections.zero? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      open_connections.zero?
    end

    def inspect = "#<#{self.class.name} url=#{url}>"

    private

    def accept_loop
      loop do
        socket = @listener.accept
        @lock.synchronize do
          @connections[socket] = Thread.new(socket) { serve(_1) }
          @opened += 1
          @peak = [@peak, @connections.size].max
        end
      end
    rescue IOError, SystemCallError
      nil # the listener was closed
    end

    def serve(socket)
      while (request = read_request(socket))
        break unless served?(socket, request)
      end
    rescue IOError, SystemCallError
      nil # the client hung up, or stop closed the socket
    ensure
      socket.close
      @lock.synchronize { @connections.delete(socket) }
    end

    # Answers one request. Returns whether the connection stays open.
    def served?(socket, request)
      reply = @fake.handle(request)
      # SO_LINGER with a zero timeout makes close send a reset, not a FIN.
      socket.setsockopt(Socket::Option.linger(true, 0)) if reply.drop == :reset
      return false if reply.drop == :reset

      request.body&.drain
      sleep(reply.delay) if reply.delay.positive?
      return false if reply.drop == :hang

      write(socket, reply.response)
      true
    end

    def read_request(socket)
      line = socket.gets("\r\n", 8192) or return
      verb, target = line.split(" ", 3)
      headers = read_headers(socket)
      length = headers.fetch("content-length", "0").to_i
      PennylaneClient::Request.new(verb: verb.downcase.to_sym, url: url + target, headers:,
                                   body: length.positive? ? Body.new(socket, length) : nil)
    end

    def read_headers(socket)
      headers = {}
      while (line = socket.gets("\r\n", 8192)) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.downcase] = value.strip
      end
      headers
    end

    def write(socket, response)
      head = ["HTTP/1.1 #{response.status}", *response.headers.map { |name, value| "#{name}: #{value}" },
              "content-length: #{response.body.bytesize}"]
      socket.write("#{head.join("\r\n")}\r\n\r\n", response.body)
    end

    # A request body read straight from the socket, `length` bytes in all.
    # It reads like an IO (`read(length, buffer)`), as FakePennylane wants.
    class Body
      def initialize(socket, length)
        @socket = socket
        @left = length
      end

      def read(length, buffer = nil)
        return nil if @left.zero?

        chunk = @socket.readpartial([length, @left].min, buffer)
        @left -= chunk.bytesize
        chunk
      end

      def drain
        buffer = String.new
        nil while read(CHUNK, buffer)
      end
    end
  end
end
