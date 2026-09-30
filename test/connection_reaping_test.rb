# frozen_string_literal: true

require "test_helper"
require "support/fake_pennylane/server"

# NetHttpTransport closes the connections of threads that have finished,
# against FakePennylane on a real socket so the server counts what is open.
class ConnectionReapingTest < Minitest::Test
  def setup
    WebMock.disable!
    @server = FakePennylane::Server.new(FakePennylane.new).start
    @transport = PennylaneClient::NetHttpTransport.new
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

  # A thread per job leaves one socket per finished thread. The next new
  # connection closes them. GC is off, as it would close them in its own time.
  def test_a_new_connection_closes_those_of_finished_threads
    GC.disable
    Array.new(10) { Thread.new { client.call(:getMe) } }.each(&:join)
    Thread.new { client.call(:getMe) }.join

    assert open_at_most?(1), "open: #{@server.open_connections}"
  ensure
    GC.enable
  end

  def test_a_new_connection_leaves_those_of_running_threads_open
    finish = Queue.new
    running = start_threads(3, finish)
    client.call(:getMe)

    assert_equal 4, @server.open_connections
  ensure
    running&.each { finish.push(true) }&.each(&:join)
  end

  private

  # Threads that each make a call, then wait on `finish`.
  def start_threads(count, finish)
    started = Queue.new
    threads = Array.new(count) { Thread.new { client.call(:getMe) && started.push(true) && finish.pop } }
    count.times { started.pop(timeout: 5) }
    threads
  end

  # Whether the server's open connections fall to `count` within a second.
  def open_at_most?(count)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
    sleep 0.01 until @server.open_connections <= count || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    @server.open_connections <= count
  end
end
