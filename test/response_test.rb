# frozen_string_literal: true

require "test_helper"

# success? is 2xx and nothing else: a redirect or an informational status
# is never the success of a call.
class ResponseTest < Minitest::Test
  def test_success_is_the_2xx_range_only
    statuses = [100, 199, 200, 204, 299, 300, 302, 304, 399, 400, 500]
    successes = statuses.select { PennylaneClient::Response.new(status: _1, headers: {}, body: "").success? }

    assert_equal [200, 204, 299], successes
  end
end
