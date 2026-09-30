# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "pennylane_client"

require "minitest/autorun"
require "webmock/minitest"

# Nothing in the suite may reach the network, Pennylane least of all.
WebMock.disable_net_connect!
