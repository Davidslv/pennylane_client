# frozen_string_literal: true

require "test_helper"
require "support/fake_pennylane/server"
require "stringio"
require "timeout"

# FakePennylane on a real socket, driven by the real NetHttpTransport.
# WebMock is off for these tests; nothing leaves 127.0.0.1.
class FakePennylaneServerTest < Minitest::Test
  def setup
    WebMock.disable!
    @fake = FakePennylane.new
    @server = FakePennylane::Server.new(@fake).start
    @transport = PennylaneClient::NetHttpTransport.new(read_timeout: 0.2)
    start_ruby_timeout_worker
    @threads = Thread.list
  end

  def teardown
    @transport.close
    @server.stop
    WebMock.enable!
    super
  end

  def client
    @client ||= PennylaneClient.new(token: "tok", base_url: @server.url, transport: @transport,
                                    limiters: PennylaneClient::LimiterRegistry.new, logger: nil, on_request: nil)
  end

  def test_answers_over_http_and_keeps_the_connection_alive
    3.times { assert_equal({ id: 1 }, client.call(:getMe)) }

    assert_equal [3, 1], [@fake.count("GET 200"), @server.connections_opened]
  end

  def test_sends_the_rate_limit_headers
    response = @transport.call(PennylaneClient::Request.new(verb: :get, url: "#{@server.url}/api/external/v2/me",
                                                            headers: { "Authorization" => "Bearer tok" }, body: nil))

    assert_equal %w[25 24], response.headers.values_at("ratelimit-limit", "ratelimit-remaining")
  end

  def test_reads_an_upload_through_the_socket
    file = StringIO.new("x" * 300_000)

    assert_operator client.call(:postFileAttachments, file:).fetch(:received), :>, 300_000
  end

  # The transport keeps idle connections for 10 s (NetHttpTransport). One the server has
  # closed meanwhile must be replaced, not written to: a write is not
  # retried, so writing to a dead socket would fail the call.
  def test_a_connection_the_server_closed_is_replaced_before_a_write
    client.call(:getMe)
    @server.close_connections

    assert @server.idle?(within: 2)
    assert_equal 1, client.call(:postJournals, code: "X", label: "Y").fetch(:id)
    assert_equal [1, 2], [@fake.count("POST 200"), @server.connections_opened]
  end

  def test_a_reset_is_a_connection_error
    @fake.inject(:reset, times: 1)

    assert_raises(PennylaneClient::ConnectionError) { client.call(:postJournals, code: "X", label: "Y") }
    assert_equal({ id: 1 }, client.call(:getMe))
  end

  def test_a_hang_is_a_timeout
    @fake.inject(:hang, times: 1, delay: 0.5)

    assert_raises(PennylaneClient::TimeoutError) { client.call(:postJournals, code: "X", label: "Y") }
  end

  def test_closed_connections_leave_no_threads_behind
    client.call(:getMe)
    @transport.close

    assert @server.idle?(within: 2), "the server still holds #{@server.open_connections} connection(s)"
    leaked = settle { Thread.list - @threads }

    assert_empty leaked, "threads left running: #{leaked.map { _1.name || _1.inspect }.join(", ")}"
  end

  private

  # On Ruby 3.3 and 3.4, Net::HTTP opens connections inside Timeout.timeout,
  # and the timeout gem starts one worker thread the first time that runs and
  # keeps it for the life of the process. Start it before taking the baseline,
  # or whichever test connects first sees one extra thread (issue #45).
  def start_ruby_timeout_worker
    Timeout.timeout(1) { nil }
  end

  # The value once it is empty, or after a second.
  def settle
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
    value = yield
    until value.empty? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
      value = yield
    end
    value
  end
end
