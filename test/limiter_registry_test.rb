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

  def test_the_default_is_process_wide
    assert_same PennylaneClient::LimiterRegistry.default, PennylaneClient::LimiterRegistry.default
  end
end
