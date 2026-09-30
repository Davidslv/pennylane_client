# frozen_string_literal: true

require "test_helper"

# A proxy's error page in Latin-1, or any stray byte, arrives as a UTF-8
# String that is not valid UTF-8. String#strip raises on it, so without
# care it escapes as Encoding::CompatibilityError, which
# `rescue PennylaneClient::Error` does not catch.
module InvalidUtf8
  LATIN1_PAGE = "<html><body>\xC9chec de la passerelle</body></html>".b
  LATIN1_JSON = "{\"label\":\"caf\xE9\"}".b

  def self.utf8(bytes) = bytes.dup.force_encoding(Encoding::UTF_8)
end

class InvalidUtf8ErrorTest < Minitest::Test
  def error_for(status, bytes)
    body = InvalidUtf8.utf8(bytes)
    PennylaneClient::Error.from_response(PennylaneClient::Response.new(status:, headers: {}, body:))
  end

  def test_a_latin1_5xx_page_is_still_a_server_error
    error = error_for(502, InvalidUtf8::LATIN1_PAGE)

    assert_instance_of PennylaneClient::ServerError, error
    assert_equal "502: <html><body>\uFFFDchec de la passerelle</body></html>", error.message
  end

  def test_keeps_the_raw_body
    error = error_for(404, InvalidUtf8::LATIN1_PAGE)

    assert_equal InvalidUtf8::LATIN1_PAGE, error.body.b
  end

  def test_parses_a_json_body_with_a_stray_byte
    error = error_for(422, "{\"error\":\"invalid\",\"message\":\"caf\xE9\"}".b)

    assert_instance_of PennylaneClient::ValidationError, error
    assert_equal "422 invalid: caf\uFFFD", error.message
  end
end

class InvalidUtf8ExecutorTest < Minitest::Test
  def executor(response)
    PennylaneClient::Executor.new(registry: PennylaneClient::Registry.default, transport: FakeTransport.new(response),
                                  base_url: "https://app.pennylane.com")
  end

  def test_a_success_body_that_is_not_utf8_raises_a_pennylane_client_error
    body = InvalidUtf8.utf8(InvalidUtf8::LATIN1_JSON)
    response = PennylaneClient::Response.new(status: 200, headers: {}, body:)
    error = assert_raises(PennylaneClient::Error) { executor(response).call(:getJournal, { id: 1 }) }

    assert_instance_of PennylaneClient::Error, error
    assert_equal 200, error.status
    assert_equal "200: the response body is not valid UTF-8", error.message
  end
end

# End to end, through the real NetHttpTransport.
class InvalidUtf8ClientTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  # No wait between retries, so the 502 is final at once.
  def client
    @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new, max_retry_wait: 0)
  end

  def test_a_latin1_502_page_raises_server_error
    stub_request(:get, "#{API}/me").to_return(status: 502, body: InvalidUtf8::LATIN1_PAGE)

    assert_raises(PennylaneClient::ServerError) { client.call(:getMe) }
  end

  def test_a_200_with_a_latin1_body_raises_a_pennylane_client_error
    stub_request(:get, "#{API}/journals/1").to_return(status: 200, body: InvalidUtf8::LATIN1_JSON)

    assert_raises(PennylaneClient::Error) { client.call(:getJournal, id: 1) }
  end
end
