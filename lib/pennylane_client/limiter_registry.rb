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
  class LimiterRegistry
    def self.default = DEFAULT

    def initialize(&build)
      @build = build || ->(_key) { Limiter.new }
      @limiters = {}
      @lock = Mutex.new
    end

    # Builds outside the lock, so a slow limiter (one that connects to a
    # store) never blocks other tokens. When two threads race, the first
    # limiter stored wins.
    def fetch(key)
      @lock.synchronize { @limiters[key] } || begin
        built = @build.call(key)
        @lock.synchronize { @limiters[key] ||= built }
      end
    end

    def inspect = "#<#{self.class.name} size=#{@lock.synchronize { @limiters.size }}>"
  end

  LimiterRegistry::DEFAULT = LimiterRegistry.new
end
