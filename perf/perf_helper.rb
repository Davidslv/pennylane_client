# frozen_string_literal: true

# Shared by rake load and rake stress. Both run against FakePennylane only:
# in process, or on a socket on 127.0.0.1. Nothing here may reach Pennylane
# (AGENTS.md), so `client` refuses any other host.
#
# WebMock is not loaded: these runs need real sockets.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__), File.expand_path("../test", __dir__)
require "pennylane_client"
require "support/fake_pennylane/server"
require "minitest/autorun"

# Helpers for the load and stress runs, and the result lines they print.
module Perf
  RESULTS = Queue.new

  module_function

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def rss_mb = (Integer(`ps -o rss= -p #{Process.pid}`.strip) / 1024.0).round(1)

  # File descriptors this process holds open, sockets included.
  def open_fds = Dir.children("/dev/fd").size

  # A Client that can only reach a FakePennylane::Server, or a FakePennylane
  # given as the transport.
  def client(token:, base_url: nil, transport: nil, **)
    raise ArgumentError, "perf runs use FakePennylane only, not #{base_url}" if base_url && !local?(base_url)
    raise ArgumentError, "a perf client needs a local base_url or a FakePennylane" unless base_url || transport

    options = { token:, transport:, logger: nil, on_request: nil, limiters: PennylaneClient::LimiterRegistry.new }
    options[:base_url] = base_url if base_url
    PennylaneClient.new(**options.compact, **)
  end

  def local?(url) = URI(url).host == "127.0.0.1"

  # Records one line of results, printed after the run for
  # docs/performance.md.
  def report(name, **values)
    RESULTS << format("%-44<name>s %<values>s", name:, values: values.map { |key, value| "#{key}=#{value}" }.join(" "))
  end

  def results = drain(RESULTS).sort

  # Everything in a Queue, as an Array.
  def drain(queue) = Array.new(queue.size) { queue.pop }

  # Runs the block in `count` threads and returns their values, failing
  # when one has not finished within `timeout` seconds: a deadlock.
  def in_threads(count, timeout:, &)
    threads = Array.new(count) { |index| Thread.new(index, &) }
    deadline = now + timeout
    stuck = threads.reject { _1.join([deadline - now, 0].max) }
    raise Minitest::Assertion, "#{stuck.size} of #{count} threads still running after #{timeout} s" if stuck.any?

    threads.map(&:value)
  end
end

Minitest.after_run do
  puts "\nResults (#{RUBY_DESCRIPTION}):"
  Perf.results.each { puts "  #{_1}" }
end
