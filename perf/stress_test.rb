# frozen_string_literal: true

require_relative "perf_helper"
require "pathname"
require "tmpdir"

# rake stress: the client while FakePennylane misbehaves, through the real
# NetHttpTransport on 127.0.0.1.
#
# Every scenario runs THREADS threads, each on its own token so the fault is
# what is measured, not the shared budget, and checks:
#
# - bounded retries: the fake sees at most 3 attempts per call;
# - the right error class for each fault;
# - no POST, PUT or DELETE sent twice after a 5xx or no response;
# - no deadlock: every thread finishes in time (Perf.in_threads);
# - no leak: afterwards the server holds no connection, and the process has
#   as many threads and file descriptors as before.
#
# `rake stress[30]` (SOAK_MINUTES=30) adds a soak: every fault in turn for
# that long, with memory sampled every 30 s. It needs at least 1.5 minutes
# to compare memory after the first minute with the end.
class StressTest < Minitest::Test
  THREADS = 8
  ATTEMPTS = 3
  GET = ->(client) { client.call(:getMe) }
  WRITES = [
    ->(client) { client.call(:postJournals, code: "STR", label: "Stress") },
    ->(client) { client.call(:ValidateAccountingSupplierInvoice, id: 1) },
    ->(client) { client.call(:deleteCustomerInvoices, id: 1) }
  ].freeze

  def setup
    @fake = FakePennylane.new
    @server = FakePennylane::Server.new(@fake).start
    @transport = PennylaneClient::NetHttpTransport.new(open_timeout: 1, read_timeout: 0.5)
    @events = Queue.new
    @threads = Thread.list.size
    @fds = Perf.open_fds
  end

  def teardown
    @server.stop
  end

  def test_a_429_storm_is_retried_a_bounded_number_of_times
    @fake.inject(:rate_limited, retry_after: 1)
    outcomes, seconds = run_calls([GET, *WRITES])

    report("429 storm, retry-after 1 s", outcomes, seconds)
    assert_equal({ PennylaneClient::RateLimitError => THREADS * 4 }, outcomes)
    assert_equal THREADS * 4 * ATTEMPTS, @fake.count("GET 429") + write_count(429), "every verb retried after a 429"
    assert_no_leaks
  end

  def test_a_429_with_a_long_retry_after_is_not_waited_for
    @fake.inject(:rate_limited, retry_after: 60)
    outcomes, seconds = run_calls([GET])

    report("429 storm, retry-after 60 s", outcomes, seconds)
    assert_equal({ PennylaneClient::RateLimitError => THREADS }, outcomes)
    assert_equal THREADS, @fake.count("GET 429"), "a wait past the 30 s cap is not taken"
    assert_operator seconds, :<, 5
    assert_no_leaks
  end

  def test_a_5xx_burst_is_retried_for_gets
    @fake.inject(:server_error, times: 2 * THREADS, status: 503)
    outcomes, seconds = run_calls([GET] * 3)

    report("5xx burst of #{2 * THREADS}, GET", outcomes, seconds)
    assert_equal [:ok], outcomes.keys - [PennylaneClient::ServerError]
    assert_equal 2 * THREADS, @fake.count("GET 503")
    assert_operator @fake.count("GET 200") + @fake.count("GET 503"), :<=, THREADS * 3 * ATTEMPTS
    assert_operator @events.size, :>, 0, "at least one retry"
    assert_no_leaks
  end

  def test_no_write_is_sent_twice_after_a_5xx
    @fake.inject(:server_error, status: 500)
    outcomes, seconds = run_calls(WRITES)

    report("5xx on every write", outcomes, seconds)
    assert_equal({ PennylaneClient::ServerError => THREADS * 3 }, outcomes)
    assert_equal THREADS * 3, write_count(500), "one attempt per write"
    assert_no_leaks
  end

  def test_a_write_the_caller_marks_repeatable_is_retried_after_a_5xx
    @fake.inject(:server_error, status: 502)
    outcomes, seconds = run_calls([->(client) { client.call(:postJournals, code: "S", label: "S", retry: :always) }])

    report("5xx on every write, retry: :always", outcomes, seconds)
    assert_equal({ PennylaneClient::ServerError => THREADS }, outcomes)
    assert_equal THREADS * ATTEMPTS, @fake.count("POST 502")
    assert_no_leaks
  end

  def test_slow_answers_arrive
    @fake.inject(:slow, delay: 0.3)
    outcomes, seconds = run_calls([GET, *WRITES])

    report("slow answers, 0.3 s of a 0.5 s read timeout", outcomes, seconds)
    assert_equal({ ok: THREADS * 4 }, outcomes)
    assert_equal 0, @events.size, "no retries"
    assert_no_leaks
  end

  def test_a_hang_is_a_timeout_and_only_gets_are_retried
    @fake.inject(:hang, delay: 1.0)
    outcomes, seconds = run_calls([GET, *WRITES])

    report("hang past the 0.5 s read timeout", outcomes, seconds)
    assert_equal({ PennylaneClient::TimeoutError => THREADS * 4 }, outcomes)
    assert_equal [THREADS * ATTEMPTS, THREADS * 3], [@fake.count("GET hang"), write_count(:hang)]
    assert_no_leaks
  end

  def test_a_reset_is_a_connection_error_and_only_gets_are_retried
    @fake.inject(:reset)
    outcomes, seconds = run_calls([GET, *WRITES])

    report("connection reset", outcomes, seconds)
    assert_equal({ PennylaneClient::ConnectionError => THREADS * 4 }, outcomes)
    assert_equal [THREADS * ATTEMPTS, THREADS * 3], [@fake.count("GET reset"), write_count(:reset)]
    assert_no_leaks
  end

  def test_malformed_json_is_an_error_and_not_retried
    @fake.inject(:malformed)
    outcomes, seconds = run_calls([GET, *WRITES])

    report("malformed JSON", outcomes, seconds)
    assert_equal({ PennylaneClient::Error => THREADS * 4 }, outcomes)
    assert_equal THREADS * 4, @fake.requests
    assert_no_leaks
  end

  # Each thread uploads 100 MB; the first attempt of each is refused with a
  # 429, so the body is rewound and streamed again.
  def test_large_uploads_stream_and_survive_a_rate_limit
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("large.pdf")
      File.open(path, "wb") { _1.truncate(100 * 1024 * 1024) } # sparse: costs no disk
      threads = 4
      @fake.inject(:rate_limited, times: threads, retry_after: 1)
      GC.start
      rss = Perf.rss_mb
      outcomes, seconds = run_calls([->(client) { client.call(:postFileAttachments, file: path) }], threads:)
      growth = Perf.rss_mb - rss

      report("#{threads} x 100 MB uploads after a 429", outcomes, seconds, rss_growth_mb: growth.round(1))
      assert_equal({ ok: threads }, outcomes)
      assert_equal [threads, threads], [@fake.count("POST 429"), @fake.count("POST 200")]
      assert_operator growth, :<, 60, "memory grew #{growth} MB for #{threads * 100} MB sent twice"
    end
    assert_no_leaks
  end

  # Separate processes have separate limiters, so together they overrun the
  # token's budget. The 429s' headers and retries absorb it: every call
  # succeeds or, at worst, raises RateLimitError.
  def test_several_processes_share_one_token
    processes = 4
    calls = 12
    started = Perf.now
    outcomes = Array.new(processes) { spawn_caller(calls) }.map { collect(_1) }.reduce({}) do |sum, tally|
      sum.merge(tally) { |_, a, b| a + b }
    end

    report("#{processes} processes x #{calls} calls, one token", outcomes, Perf.now - started,
           too_many_requests: @fake.count("GET 429"))
    assert_equal [:ok], outcomes.keys - ["PennylaneClient::RateLimitError"]
    assert_equal processes * calls, outcomes.values.sum
    assert_operator @fake.count("GET 200") + @fake.count("GET 429"), :<=, processes * calls * ATTEMPTS
    assert_no_leaks
  end

  def test_soak
    minutes = Float(ENV.fetch("SOAK_MINUTES", "0"))
    skip "set SOAK_MINUTES to soak" unless minutes.positive?
    raise ArgumentError, "a soak needs at least 1.5 minutes, got #{minutes}" if minutes < 1.5

    samples = soak(minutes * 60)
    growth = (samples.last - samples[1]).round(1)

    Perf.report("stress: soak #{minutes} min", requests: @fake.requests, rss_mb: samples.map(&:round).join(","),
                                               growth_after_first_minute_mb: growth)
    assert_operator growth, :<, 30, "memory grew #{growth} MB after the first minute"
    assert_no_leaks
  end

  private

  def client(token)
    Perf.client(token:, base_url: @server.url, transport: @transport,
                on_request: ->(event) { @events << event if event[:type] == :retry })
  end

  # Each thread makes every call in `calls` once, on its own token. Returns
  # the tally of outcomes (:ok or an error class) and the seconds taken.
  def run_calls(calls, threads: THREADS)
    started = Perf.now
    outcomes = Perf.in_threads(threads, timeout: 120) do |index|
      api = client("stress-#{name}-#{index}")
      calls.map { |call| outcome { call.call(api) } }
    ensure
      @transport.close
    end
    [outcomes.flatten.tally, Perf.now - started]
  end

  def outcome
    yield
    :ok
  rescue PennylaneClient::Error => e
    e.class
  end

  def write_count(outcome) = %w[POST PUT DELETE].sum { @fake.count("#{_1} #{outcome}") }

  # A child process that makes `calls` calls on the shared token and writes
  # its tally to a pipe. exit! skips Minitest's at_exit in the child.
  def spawn_caller(calls)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      transport = PennylaneClient::NetHttpTransport.new
      client = Perf.client(token: "shared", base_url: @server.url, transport:)
      tally = Array.new(calls) { outcome { client.call(:getMe) } }.map(&:to_s).tally
      writer.write(JSON.generate(tally))
      exit!(0)
    end
    writer.close
    [pid, reader]
  end

  def collect((pid, reader))
    tally = JSON.parse(reader.read)
    Process.wait(pid)
    tally.transform_keys { _1 == "ok" ? :ok : _1 }
  ensure
    reader.close
  end

  # Every fault in turn, 10 s each, until the time is up. Returns RSS
  # samples, one every 30 s.
  def soak(seconds)
    faults = [[:server_error, { times: 20 }], [:slow, { delay: 0.2 }], [:reset, { times: 5 }],
              [:malformed, { times: 5 }], [:rate_limited, { times: 10 }], [:hang, { times: 3, delay: 1.0 }], [nil, {}]]
    deadline = Perf.now + seconds
    sampler = Thread.new { sample_until(deadline) }
    faults.cycle do |kind, options|
      break if Perf.now > deadline

      kind ? @fake.inject(kind, **options) : @fake.heal
      turn_ends = [deadline, Perf.now + 10].min
      run_calls([GET, *WRITES, GET]) while Perf.now < turn_ends
    end
    sampler.value
  end

  def sample_until(deadline)
    samples = [Perf.rss_mb]
    samples << Perf.rss_mb while Perf.now < deadline && sleep(30)
    samples
  end

  def report(scenario, outcomes, seconds, **extra)
    Perf.report("stress: #{scenario}", outcomes: outcomes.map { |key, value| "#{key}:#{value}" }.join(","),
                                       attempts: @fake.requests, retries: @events.size, seconds: seconds.round(1),
                                       **extra)
  end

  def assert_no_leaks
    assert @server.idle?(within: 5), "the server still holds #{@server.open_connections} connection(s)"
    assert_equal @threads, Perf.settle(@threads) { Thread.list.size }, "threads left running"
    assert_equal @fds, Perf.settle(@fds) { Perf.open_fds }, "file descriptors left open"
  end
end
