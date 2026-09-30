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

  # After fork the parent's other threads look finished in the child. The
  # child must leave their connections alone: finishing a TLS connection
  # sends close_notify on a socket the parent is still using. It must not
  # reuse the forking thread's connection either.
  def test_a_forked_child_neither_closes_nor_reuses_the_parents_connections
    skip "no fork on this platform" unless Process.respond_to?(:fork)

    worker = Worker.new
    call_on(worker)
    opened = @server.connections_opened

    assert_equal({ finished: 0, opened: 2 }, in_child { call_on(Worker.new) })
    call_on(worker)

    assert_equal opened + 2, @server.connections_opened, "the parent reconnected"
  ensure
    worker&.stop
  end

  private

  # A thread that runs one job at a time and keeps its connection between.
  class Worker
    def initialize
      @jobs = Queue.new
      @done = Queue.new
      @thread = Thread.new { while (job = @jobs.pop) do @done.push(job.call) end }
    end

    def run(&job) = @jobs.push(job) && @done.pop(timeout: 5)
    def stop = @jobs.push(nil) && @thread.join
  end

  # A call on this thread, then one on the worker's.
  def call_on(worker)
    client.call(:getMe)
    worker.run { client.call(:getMe) }
  end

  # Counts Net::HTTP#finish calls in a forked child.
  module CountFinish
    CALLS = Queue.new

    def finish
      CALLS.push(true)
      super
    end
  end

  # Runs the block in a forked child and returns how many connections it
  # finished and how many the server saw it open.
  def in_child(&)
    reader, writer = IO.pipe
    before = @server.connections_opened
    pid = fork { report_from_child(reader, writer, &) }
    writer.close
    finished = reader.read.to_i
    Process.wait(pid)
    { finished:, opened: @server.connections_opened - before }
  end

  def report_from_child(reader, writer)
    reader.close
    Net::HTTP.prepend(CountFinish)
    yield
    writer.write(CountFinish::CALLS.size)
    exit!(0)
  end

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
