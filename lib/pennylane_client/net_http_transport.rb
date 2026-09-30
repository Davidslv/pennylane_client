# frozen_string_literal: true

require "net/http"
require "openssl"

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
  # - Keep-alive, with one connection per host per thread, so threads never
  #   share a socket and no lock is needed.
  # - Timeouts: open 5 s, read 30 s, write 30 s (proposal 0001).
  # - Never retries. Net::HTTP retries idempotent verbs once by default,
  #   and PUT and DELETE have side effects at Pennylane (D5).
  class NetHttpTransport
    VERBS = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.freeze

    TIMEOUT_ERRORS = [Timeout::Error].freeze
    CONNECTION_ERRORS = [IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::ProtocolError,
                         Net::HTTPBadResponse].freeze

    def initialize(open_timeout: 5, read_timeout: 30, write_timeout: 30)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @write_timeout = write_timeout
      @key = :"pennylane_client_connections_#{object_id}"
    end

    def call(request)
      uri = URI(request.url)
      http = connection(uri)
      http.start unless http.started?
      response = http.request(build(request, uri))
      Response.new(status: response.code.to_i, headers: response.each_header.to_h, body: response.body.to_s)
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
      http.max_retries = 0
      http
    end

    def build(request, uri)
      http_request = VERBS.fetch(request.verb).new(uri.request_uri, request.headers)
      http_request.body = request.body if request.body
      http_request
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
end
