# frozen_string_literal: true

require "test_helper"
require "pp"

class AuthTest < Minitest::Test
  TOKEN = "pl-secret-token-7f3a9c"

  def setup
    ok = PennylaneClient::Response.new(status: 200, headers: {}, body: "")
    @transport = FakeTransport.new(ok, ok)
    @request = PennylaneClient::Request.new(verb: :get, url: "https://app.pennylane.com/api/external/v2/me",
                                            headers: { "Accept" => "application/json" }, body: nil)
  end

  def auth(token) = PennylaneClient::Middleware::Auth.new(@transport, token)

  def sent_token = @transport.requests.last.headers["Authorization"]

  def test_sends_a_string_token_as_a_bearer_header
    auth(TOKEN).call(@request)

    assert_equal "Bearer #{TOKEN}", sent_token
    assert_equal "application/json", @transport.requests.last.headers["Accept"]
  end

  def test_asks_a_token_provider_on_every_request
    tokens = %w[first second]
    middleware = auth(-> { tokens.shift })

    middleware.call(@request)

    assert_equal "Bearer first", sent_token
    middleware.call(@request)

    assert_equal "Bearer second", sent_token
  end

  def test_refuses_a_bad_token_from_a_provider_without_echoing_it
    error = assert_raises(ArgumentError) { auth(-> { "#{TOKEN}\nX-Evil: 1" }).call(@request) }

    refute_includes error.message, TOKEN
    assert_empty @transport.requests
  end

  def test_refuses_a_bad_string_token_when_built
    assert_raises(ArgumentError) { auth("") }
    assert_raises(ArgumentError) { auth(nil) }
    assert_raises(ArgumentError) { auth("two words") }
  end

  def test_inspect_hides_the_token
    middleware = auth(TOKEN)

    refute_includes middleware.inspect, TOKEN
    refute_includes PP.pp(middleware, +""), TOKEN
  end
end
