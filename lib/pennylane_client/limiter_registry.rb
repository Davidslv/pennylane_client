# frozen_string_literal: true

module PennylaneClient
  # One Limiter per token, shared by every Client and thread that uses the
  # registry. Keys are SHA-256 digests of the token, never the token.
  #
  # Every Client uses LimiterRegistry.default unless given another. To share
  # a budget across processes, pass a registry whose block builds your own
  # limiter (anything with `acquire` and `update(remaining:, reset_at:)`):
  #
  #   PennylaneClient.new(token:, limiters: PennylaneClient::LimiterRegistry.new { |key| RedisLimiter.new(key) })
  #
  # Tokens rotate (an OAuth token provider) and multi-company apps hold one
  # per company, so a limiter no one has fetched for `idle_after` seconds is
  # dropped, and the registry holds only the tokens in use. A Limiter is
  # dropped only once its window has ended and no thread waits on it, when a
  # new one for the same token is a full bucket just the same. A limiter
  # that does not answer `idle?` is dropped on time alone.
  #
  # The sweep runs when a new limiter is stored, at most once per
  # `idle_after`, so a fetch of a known token does no more work than before.
  class LimiterRegistry
    IDLE_AFTER = 60.0

    Entry = Struct.new(:limiter, :used_at)
    private_constant :Entry

    def self.default = DEFAULT

    def initialize(idle_after: IDLE_AFTER, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, &build)
      @build = build || ->(_key) { Limiter.new }
      @idle_after = idle_after.to_f
      @clock = clock
      @limiters = {}
      @lock = Mutex.new
      @sweep_at = nil
    end

    # Builds outside the lock, so a slow limiter (one that connects to a
    # store) never blocks other tokens. When two threads race, the first
    # limiter stored wins.
    def fetch(key)
      @lock.synchronize { touch(key) } || begin
        built = @build.call(key)
        @lock.synchronize { touch(key) || store(key, built) }
      end
    end

    def inspect = "#<#{self.class.name} size=#{@lock.synchronize { @limiters.size }}>"

    private

    def touch(key)
      entry = @limiters[key] or return
      entry.used_at = @clock.call
      entry.limiter
    end

    def store(key, limiter)
      now = @clock.call
      sweep(now)
      @limiters[key] = Entry.new(limiter, now)
      limiter
    end

    # A thread that fetched a limiter calls `acquire` on it straight away,
    # so one fetched within `idle_after` is kept. A call already under way
    # may still `update` a dropped limiter; the next response corrects the
    # new one.
    def sweep(now)
      return if @sweep_at && now < @sweep_at

      @sweep_at = now + @idle_after
      @limiters.delete_if { |_key, entry| now - entry.used_at >= @idle_after && idle?(entry.limiter) }
    end

    def idle?(limiter) = !limiter.respond_to?(:idle?) || limiter.idle?
  end

  LimiterRegistry::DEFAULT = LimiterRegistry.new
end
