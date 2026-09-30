# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"

class ConfigurationTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def setup
    @saved = PennylaneClient.configuration.dup
  end

  # super is WebMock's reset; without it this test's stubs outlive it.
  def teardown
    PennylaneClient.configure do |config|
      config.logger = @saved.logger
      config.on_request = @saved.on_request
    end
    super
  end

  def test_defaults_to_no_logger_and_no_callback
    config = PennylaneClient::Configuration.new

    assert_nil config.logger
    assert_nil config.on_request
  end

  def test_clients_built_after_configure_log_and_emit_events
    log = StringIO.new
    events = []
    PennylaneClient.configure do |config|
      config.logger = Logger.new(log)
      config.on_request = events.method(:<<)
    end
    stub_request(:get, "#{API}/me").to_return(status: 200, body: "{}")

    PennylaneClient.new(token: "tok").call(:getMe)

    assert_includes log.string, "getMe GET /api/external/v2/me -> 200"
    assert_equal :getMe, events.fetch(0)[:operation_id]
  end

  def test_a_client_can_override_the_configuration
    events = []
    PennylaneClient.configure { _1.on_request = ->(_) { flunk "global callback used" } }
    stub_request(:get, "#{API}/me").to_return(status: 200, body: "{}")

    PennylaneClient.new(token: "tok", on_request: events.method(:<<)).call(:getMe)

    assert_equal 1, events.size
  end
end
