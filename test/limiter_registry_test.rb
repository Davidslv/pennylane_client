# frozen_string_literal: true

require "test_helper"

class LimiterRegistryTest < Minitest::Test
  def test_one_limiter_per_key
    registry = PennylaneClient::LimiterRegistry.new

    assert_same registry.fetch("a"), registry.fetch("a")
    refute_same registry.fetch("a"), registry.fetch("b")
  end

  def test_threads_asking_for_the_same_key_share_one_limiter
    registry = PennylaneClient::LimiterRegistry.new

    limiters = Array.new(16) { Thread.new { registry.fetch("a") } }.map(&:value)

    assert_equal 1, limiters.uniq(&:object_id).size
  end

  def test_builds_limiters_with_the_block
    registry = PennylaneClient::LimiterRegistry.new { |key| "limiter for #{key}" }

    assert_equal "limiter for a", registry.fetch("a")
  end

  # A token provider that rotates tokens, or one Client per company, keys a
  # new limiter per token. Limiters left idle are dropped, so the registry
  # holds only the tokens in use.
  def test_memory_stays_bounded_while_tokens_rotate
    time = VirtualClock.new
    registry = registry_on(time)

    100.times do |minute|
      1_000.times { |n| registry.fetch("token-#{minute}-#{n}").acquire }
      time.sleeper.call(60)
    end

    assert_operator size(registry), :<=, 2_000
  end

  def test_a_token_in_use_keeps_its_limiter
    time = VirtualClock.new
    registry = registry_on(time)
    limiter = registry.fetch("live")

    10.times do
      time.sleeper.call(59)
      registry.fetch("other-#{time.now}")
      assert_same limiter, registry.fetch("live")
    end
  end

  # A dropped limiter comes back as a full bucket, so one is only dropped
  # once its window has ended and no thread waits on it.
  def test_a_limiter_is_not_dropped_while_its_window_is_open
    time = VirtualClock.new
    registry = registry_on(time, period: 600)
    limiter = registry.fetch("slow")
    25.times { limiter.acquire }

    time.sleeper.call(120)
    registry.fetch("other")

    assert_same limiter, registry.fetch("slow")
  end

  def test_a_limiter_is_not_dropped_while_a_thread_waits_on_it
    time = VirtualClock.new
    wake = Queue.new
    limiter = PennylaneClient::Limiter.new(limit: 1, clock: time.clock, sleeper: ->(_) { wake.pop })
    registry = PennylaneClient::LimiterRegistry.new(clock: time.clock) { limiter }
    registry.fetch("busy").acquire

    kept = while_waiting(limiter, wake) { time.sleeper.call(120) && registry.fetch("other") && size(registry) }

    assert_equal 2, kept
  end

  def test_limiters_it_did_not_build_are_dropped_on_time_alone
    time = VirtualClock.new
    registry = PennylaneClient::LimiterRegistry.new(clock: time.clock) { Object.new }
    registry.fetch("a")

    time.sleeper.call(120)
    registry.fetch("b")

    assert_equal 1, size(registry)
  end

  def test_the_default_is_process_wide
    assert_same PennylaneClient::LimiterRegistry.default, PennylaneClient::LimiterRegistry.default
  end

  private

  def registry_on(time, period: 5)
    PennylaneClient::LimiterRegistry.new(clock: time.clock) do
      PennylaneClient::Limiter.new(period:, clock: time.clock, sleeper: time.sleeper)
    end
  end

  # Runs the block while another thread sleeps in `limiter.acquire`.
  def while_waiting(limiter, wake)
    waiter = Thread.new { limiter.acquire }
    Thread.pass until waiter.status == "sleep"
    yield
  ensure
    wake.push(true)
    waiter.join
  end

  def size(registry) = registry.inspect[/size=(\d+)/, 1].to_i
end
