# frozen_string_literal: true

module PennylaneClient
  # A token bucket for one token: `limit` calls per window of `period`
  # seconds, refilled in full when the window ends. Pennylane allows 25
  # requests per 5 seconds and reports its own window in every response
  # (`ratelimit-remaining`, and `ratelimit-reset` as a Unix timestamp), so
  # the bucket follows the same shape and `update` can correct it.
  #
  # The clock is wall-clock seconds because `ratelimit-reset` is. A clock
  # jump costs at most one window: a reset already past, or more than one
  # window away (plus a second, as the header is whole seconds), is ignored.
  #
  # Thread-safe. The lock is held only to take a call or read a header,
  # never while sleeping.
  class Limiter
    def initialize(limit: 25, period: 5.0, clock: -> { Time.now.to_f }, sleeper: ->(seconds) { sleep(seconds) })
      @limit = limit
      @period = period.to_f
      @clock = clock
      @sleeper = sleeper
      @lock = Mutex.new
      @remaining = limit
      @reset_at = nil
    end

    # Takes one call from the bucket, sleeping until the window resets when
    # it is empty. Returns the seconds slept.
    def acquire
      waited = 0.0
      loop do
        wait = @lock.synchronize { take }
        return waited unless wait.positive?

        @sleeper.call(wait)
        waited += wait
      end
    end

    # Corrects the bucket from a response's rate-limit headers. Pennylane's
    # window end wins. The count only ever goes down: another process may be
    # spending the same token, and requests still in flight are not in
    # Pennylane's count yet.
    def update(remaining:, reset_at: nil)
      @lock.synchronize do
        now = @clock.call
        next if reset_at && (reset_at <= now || reset_at > now + @period + 1)

        refill(now)
        @remaining = [@remaining, remaining].min
        @reset_at = reset_at if reset_at
      end
    end

    def inspect = "#<#{self.class.name} limit=#{@limit} period=#{@period}>"

    private

    # Returns 0 when a call was taken, else the seconds until the reset.
    def take
      now = @clock.call
      refill(now)
      return @reset_at - now unless @remaining.positive?

      @remaining -= 1
      0.0
    end

    def refill(now)
      return if @reset_at && now < @reset_at

      @remaining = @limit
      @reset_at = now + @period
    end
  end
end
