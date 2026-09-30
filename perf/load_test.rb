# frozen_string_literal: true

require_relative "perf_helper"

# rake load: the client under steady load, against FakePennylane.
#
# - Several threads on one token sustain close to Pennylane's 25 requests
#   per 5 s and never see a 429, through the real NetHttpTransport, one
#   keep-alive connection per thread.
# - Paginating 100k items keeps memory flat: the walk holds one page at a
#   time.
#
# LOAD_THREADS and LOAD_SECONDS change the first run's size.
class LoadTest < Minitest::Test
  THREADS = Integer(ENV.fetch("LOAD_THREADS", "8"))
  SECONDS = Float(ENV.fetch("LOAD_SECONDS", "20"))
  LIMIT = 25
  PERIOD = 5

  # One sustained run: the calls made, the seconds taken, and each client
  # event as [type, Unix time].
  Run = Data.define(:calls, :seconds, :events, :fake, :server) do
    def count(type) = events.count { _1.first == type }

    # Requests sent in each of Pennylane's windows, leaving out the first
    # and last, which the run only partly covers.
    def full_windows
      events.filter_map { |type, at| (at / PERIOD).floor if type == :request }.tally.sort.map(&:last)[1...-1]
    end
  end

  def test_threads_sustain_the_rate_limit_with_no_429s
    run = sustain
    windows = run.full_windows

    report_sustain(run, windows)
    assert_equal [0, 0], [run.fake.count("GET 429"), run.count(:retry)], "429s seen by the fake, retries by the client"
    assert_operator windows.min, :>=, 0.9 * LIMIT, "requests per full #{PERIOD} s window: #{windows}"
    assert_equal THREADS, run.server.connections_opened, "one keep-alive connection per thread"
  end

  def test_paginates_100k_items_in_flat_memory
    fake = FakePennylane.new(limit: 1_000_000).collection("/api/external/v2/customer_invoices", size: 100_000)
    unlimited = PennylaneClient::LimiterRegistry.new { PennylaneClient::Limiter.new(limit: 1_000_000) }
    rss = Perf.rss_mb
    count, samples, seconds = walk(Perf.client(token: "load", transport: fake, limiters: unlimited))
    growth = samples.last - samples[1]

    Perf.report("load: paginate 100k items", items: count, pages: fake.count("GET 200"), seconds: seconds.round(1),
                                             live_slots_growth: growth, rss_mb: "#{rss}->#{Perf.rss_mb}")
    assert_equal 100_000, count
    assert_operator growth, :<, 50_000, "live objects grew by #{growth} between 20k and 100k items"
  end

  private

  # Every thread calls getMe until the time is up.
  def sustain
    fake = FakePennylane.new
    server = FakePennylane::Server.new(fake).start
    events = Queue.new
    transport = PennylaneClient::NetHttpTransport.new
    client = Perf.client(token: "load", base_url: server.url, transport:,
                         on_request: ->(event) { events << [event[:type], Time.now.to_f] })
    started = Perf.now
    calls = Perf.in_threads(THREADS, timeout: SECONDS + 30) { call_until(client, transport, started + SECONDS) }
    seconds = Perf.now - started
    Run.new(calls: calls.sum, seconds:, events: Perf.drain(events), fake:, server:)
  ensure
    server&.stop
  end

  def call_until(client, transport, deadline)
    calls = 0
    while Perf.now < deadline
      client.call(:getMe)
      calls += 1
    end
    calls
  ensure
    transport.close
  end

  # Walks every item, sampling live objects after a full GC every 10k items.
  def walk(client)
    started = Perf.now
    samples = []
    count = 0
    client.paginate(:getCustomerInvoices).each do
      count += 1
      next unless (count % 10_000).zero?

      GC.start
      samples << GC.stat(:heap_live_slots)
    end
    [count, samples, Perf.now - started]
  end

  def report_sustain(run, windows)
    Perf.report("load: #{THREADS} threads, one token, #{SECONDS.to_i} s",
                calls: run.calls, seconds: run.seconds.round(1), per_full_window: windows.minmax.uniq.join("-"),
                of_limit: "#{(100.0 * windows.sum / (windows.size * LIMIT)).round}%",
                too_many_requests: run.fake.count("GET 429"), retries: run.count(:retry),
                limiter_waits: run.count(:wait), connections: run.server.connections_opened)
  end
end
