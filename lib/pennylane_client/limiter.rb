# frozen_string_literal: true

module PennylaneClient
  # A token bucket for one token: `limit` calls per window of `period`
  # seconds, refilled in full when the window ends. Pennylane allows 25
  # requests per 5 seconds and reports its own window in every response
  # (`ratelimit-remaining`, and `ratelimit-reset` as a Unix timestamp), so
  # the bucket follows the same shape and `update` can correct it.
  #
  # The clock is wall-clock seconds because `ratelimit-reset` is. A clock
  # jump or skew costs at most one window: a reset already past, or more
  # than one window away (plus a second, as the header is whole seconds),
  # is ignored, and the bucket keeps its own window end. The remaining
  # count does not depend on the clock, so it is applied either way.
  #
  # Thread-safe. The lock is held only to take a call or read a header,
  # never while sleeping.
  #
  # @api private
  class Limiter
    def initialize(limit: 25, period: 5.0, clock: -> { Time.now.to_f }, sleeper: ->(seconds) { sleep(seconds) })
      @limit = limit
      @period = period.to_f
      @clock = clock
      @sleeper = sleeper
      @lock = Mutex.new
      @remaining = limit
      @reset_at = nil
      @waiting = 0
    end

    # Takes one call from the bucket, sleeping until the window resets when
    # it is empty. Returns the seconds slept.
    def acquire
      waited = 0.0
      loop do
        wait = @lock.synchronize { take.tap { @waiting += 1 if _1.positive? } }
        return waited unless wait.positive?

        sleep_for(wait)
        waited += wait
      end
    end

    # Whether a new Limiter would do the same: the window has ended and no
    # thread waits on this one. LimiterRegistry drops idle limiters.
    def idle?
      @lock.synchronize { @waiting.zero? && (@reset_at.nil? || @clock.call >= @reset_at) }
    end

    # Corrects the bucket from a response's rate-limit headers. Pennylane's
    # window end wins when it is plausible. The count only ever goes down:
    # another process may be spending the same token, and requests still in
    # flight are not in Pennylane's count yet.
    def update(remaining:, reset_at: nil)
      @lock.synchronize do
        now = @clock.call
        refill(now)
        @remaining = [@remaining, remaining].min
        @reset_at = reset_at if reset_at && plausible?(reset_at, now)
      end
    end

    def inspect = "#<#{self.class.name} limit=#{@limit} period=#{@period}>"

    private

    def sleep_for(wait)
      @sleeper.call(wait)
    ensure
      @lock.synchronize { @waiting -= 1 }
    end

    # Returns 0 when a call was taken, else the seconds until the reset.
    def take
      now = @clock.call
      refill(now)
      return @reset_at - now unless @remaining.positive?

      @remaining -= 1
      0.0
    end

    # A reset already past, or further than one window away, means the
    # clocks disagree.
    def plausible?(reset_at, now) = reset_at > now && reset_at <= now + @period + 1

    def refill(now)
      return if @reset_at && now < @reset_at

      @remaining = @limit
      @reset_at = now + @period
    end
  end
end
