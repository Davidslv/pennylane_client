# frozen_string_literal: true

require "test_helper"
require "net/http"

# The suite must never reach Pennylane (AGENTS.md). WebMock enforces it.
class NetworkGuardTest < Minitest::Test
  def test_real_http_is_blocked
    assert_raises(WebMock::NetConnectNotAllowedError) do
      Net::HTTP.get(URI("https://app.pennylane.com/api/external/v2/me"))
    end
  end
end
