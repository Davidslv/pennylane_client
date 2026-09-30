# frozen_string_literal: true

require "test_helper"

class LimiterTest < Minitest::Test
  def setup
    @time = VirtualClock.new
    @limiter = PennylaneClient::Limiter.new(clock: @time.clock, sleeper: @time.sleeper)
  end

  def test_25_calls_pass_and_the_26th_waits_within_one_5_second_window
    waits = Array.new(25) { @limiter.acquire }

    assert_equal [0.0] * 25, waits
    assert_empty @time.sleeps

    waited = @limiter.acquire

    assert_in_delta 5.0, waited
    assert_equal [5.0], @time.sleeps
  end

  def test_a_new_window_starts_after_the_reset
    25.times { @limiter.acquire }
    @limiter.acquire

    assert_equal [0.0] * 24, Array.new(24) { @limiter.acquire }
    assert_in_delta 5.0, @limiter.acquire
  end

  def test_a_window_left_idle_refills
    10.times { @limiter.acquire }
    @time.sleeper.call(6)

    assert_equal [0.0] * 25, Array.new(25) { @limiter.acquire }
  end

  def test_headers_drain_the_local_bucket
    @limiter.acquire
    @limiter.update(remaining: 0, reset_at: @time.now + 3)

    assert_in_delta 3.0, @limiter.acquire
  end

  def test_headers_never_add_calls_to_the_window
    20.times { @limiter.acquire }
    @limiter.update(remaining: 24, reset_at: @time.now + 5)

    assert_equal [0.0] * 5, Array.new(5) { @limiter.acquire }
    assert_operator @limiter.acquire, :>, 0
  end

  # The server's window ends later than ours, so ours must not refill first.
  def test_a_later_server_reset_moves_the_window_end
    25.times { @limiter.acquire }
    @limiter.update(remaining: 0, reset_at: @time.now + 5.5)

    assert_in_delta 5.5, @limiter.acquire
  end

  # A reset in the past or beyond one window means the clocks disagree. The
  # reset is not trusted, but the count is: it waits out the local window.
  def test_a_skewed_reset_is_ignored_but_the_remaining_count_still_drains_the_bucket
    @limiter.acquire
    @limiter.update(remaining: 0, reset_at: @time.now + 60)

    assert_in_delta 5.0, @limiter.acquire
  end

  def test_a_reset_already_past_still_drains_the_bucket_until_the_local_window_ends
    @limiter.acquire
    @time.sleeper.call(1)
    @limiter.update(remaining: 0, reset_at: @time.now - 3)

    assert_in_delta 4.0, @limiter.acquire
  end

  def test_a_skewed_reset_never_moves_the_local_window
    @limiter.acquire
    @limiter.update(remaining: 1, reset_at: @time.now + 3600)
    @limiter.update(remaining: 1, reset_at: @time.now - 1)

    assert_equal [0.0, 5.0], Array.new(2) { @limiter.acquire }
  end

  def test_limit_and_period_are_configurable
    limiter = PennylaneClient::Limiter.new(limit: 2, period: 1, clock: @time.clock, sleeper: @time.sleeper)

    assert_equal [0.0, 0.0, 1.0], Array.new(3) { limiter.acquire }
  end

  # Another thread must be able to update the bucket while one sleeps.
  def test_releases_its_lock_while_sleeping
    asleep = Queue.new
    limiter = PennylaneClient::Limiter.new(limit: 1, period: 60, sleeper: ->(_) { asleep.push(true).then { sleep } })
    limiter.acquire
    sleeper = Thread.new { limiter.acquire }
    asleep.pop

    updated = Thread.new { limiter.update(remaining: 1) }.join(1)
    sleeper.kill.join

    refute_nil updated, "update blocked while another thread slept"
  end
end
