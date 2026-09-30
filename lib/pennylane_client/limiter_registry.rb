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

    def fetch(key)
      @lock.synchronize { @limiters[key] ||= @build.call(key) }
    end

    def inspect = "#<#{self.class.name} size=#{@lock.synchronize { @limiters.size }}>"
  end

  LimiterRegistry::DEFAULT = LimiterRegistry.new
end
