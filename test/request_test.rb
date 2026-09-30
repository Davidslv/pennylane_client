# frozen_string_literal: true

require "test_helper"
require "pp"

class RequestTest < Minitest::Test
  def test_inspect_hides_the_authorization_header
    request = PennylaneClient::Request.new(
      verb: :get, url: "https://app.pennylane.com/api/external/v2/me",
      headers: { "Authorization" => "Bearer secret-token-123", "Accept" => "application/json" }, body: nil
    )

    refute_includes request.inspect, "secret-token-123"
    refute_includes request.to_s, "secret-token-123"
    refute_includes PP.pp(request, +""), "secret-token-123"
    assert_includes request.inspect, "[FILTERED]"
    assert_includes request.inspect, "application/json"
  end
end
