# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "pennylane_client"

require "minitest/autorun"
require "webmock/minitest"

# Nothing in the suite may reach the network, Pennylane least of all.
WebMock.disable_net_connect!

# Records each Request and answers with the next canned Response, or raises
# it when it is an Exception.
class FakeTransport
  attr_reader :requests

  def initialize(*responses)
    @responses = responses
    @requests = []
  end

  def call(request)
    @requests << request
    response = @responses.shift
    raise response if response.is_a?(Exception)

    response
  end
end
