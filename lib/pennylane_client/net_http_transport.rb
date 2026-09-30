# frozen_string_literal: true

require "net/http"
require "openssl"
require "zlib"

module PennylaneClient
  # A Transport turns a Request into a Response. Anything with
  # `call(request) -> Response` is one, so tests, load runs and stress runs
  # swap in their own without touching the rest of the client.
  #
  # A Transport raises ConnectionError or TimeoutError when no response
  # arrives. It never raises for an HTTP status; the Executor maps those.
  #
  # NetHttpTransport is the default, on Net::HTTP from the standard library:
  #
  # - Keep-alive, with one connection per host per fiber (Thread#[] is
  #   fiber-local), so threads and fibers never share a socket and no lock
  #   is needed. Clients share NetHttpTransport.default, so building a
  #   Client per request or per token opens no new sockets; the token
  #   travels in each request, not in the connection.
  # - Timeouts: open 5 s, read 30 s, write 30 s (proposal 0001). An upload
  #   gets 300 s to read and write, then the connection goes back to 30 s.
  # - An idle connection is kept for 30 s (`keep_alive_timeout`). Net::HTTP
  #   drops it after 2 s by default, and a rate-limit wait lasts up to 5 s,
  #   so a busy token would reconnect after every wait (docs/performance.md).
  #   Net::HTTP still reconnects when the server has closed the connection.
  # - A body that responds to `read` (Multipart) is rewound and streamed
  #   as `body_stream`; a String body is sent as is.
  # - Never retries. Net::HTTP retries idempotent verbs once by default,
  #   and PUT and DELETE have side effects at Pennylane (D5).
  class NetHttpTransport
    VERBS = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.freeze

    TIMEOUT_ERRORS = [Timeout::Error].freeze
    CONNECTION_ERRORS = [IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::ProtocolError,
                         Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Zlib::Error].freeze

    # The process-wide transport every Client uses unless given another.
    def self.default = DEFAULT

    def initialize(open_timeout: 5, read_timeout: 30, write_timeout: 30, upload_timeout: 300, keep_alive_timeout: 30)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @write_timeout = write_timeout
      @upload_timeout = upload_timeout
      @keep_alive_timeout = keep_alive_timeout
      @key = :"pennylane_client_connections_#{object_id}"
    end

    def call(request)
      uri = URI(request.url)
      http = connection(uri)
      http.start unless http.started?
      to_response(send_request(http, request, uri))
    rescue *TIMEOUT_ERRORS => e
      fail_with(TimeoutError, e, uri)
    rescue *CONNECTION_ERRORS => e
      fail_with(ConnectionError, e, uri)
    end

    # Closes this thread's connections.
    def close
      connections.each_value { _1.finish if _1.started? }
      connections.clear
    end

    private

    def connections
      Thread.current[@key] ||= {}
    end

    def connection(uri)
      connections["#{uri.host}:#{uri.port}"] ||= build_connection(uri)
    end

    def build_connection(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      http.write_timeout = @write_timeout
      http.keep_alive_timeout = @keep_alive_timeout
      http.max_retries = 0
      http
    end

    def send_request(http, request, uri)
      return http.request(build(request, uri)) unless stream?(request.body)

      request.body.rewind
      http.read_timeout = http.write_timeout = @upload_timeout
      begin
        http.request(build(request, uri))
      ensure
        http.read_timeout = @read_timeout
        http.write_timeout = @write_timeout
      end
    end

    def stream?(body) = body.respond_to?(:read)

    def build(request, uri)
      http_request = VERBS.fetch(request.verb).new(uri.request_uri, request.headers)
      if stream?(request.body)
        http_request.body_stream = request.body
      elsif request.body
        http_request.body = request.body
      end
      http_request
    end

    # Net::HTTP returns the body as bytes; Pennylane sends UTF-8.
    def to_response(response)
      body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      Response.new(status: response.code.to_i, headers: response.each_header.to_h, body:)
    end

    def fail_with(klass, error, uri)
      drop(uri)
      raise klass, "#{error.class}: #{error.message} (#{uri.host})"
    end

    def drop(uri)
      http = connections.delete("#{uri.host}:#{uri.port}")
      http.finish if http&.started?
    rescue IOError
      nil
    end
  end

  NetHttpTransport::DEFAULT = NetHttpTransport.new
end
