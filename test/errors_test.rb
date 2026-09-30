# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test
  def response(status, body = "", headers = {})
    PennylaneClient::Response.new(status:, headers:, body:)
  end

  def error_for(...)
    PennylaneClient::Error.from_response(response(...))
  end

  # One test per class, statuses written by hand from the errors guide.
  def assert_maps(status, klass)
    error = error_for(status)

    assert_instance_of klass, error, "status #{status}"
    assert_equal status, error.status
  end

  def test_400_is_a_validation_error = assert_maps(400, PennylaneClient::ValidationError)
  def test_401_is_an_authentication_error = assert_maps(401, PennylaneClient::AuthenticationError)
  def test_403_is_a_permission_error = assert_maps(403, PennylaneClient::PermissionError)
  def test_404_is_a_not_found_error = assert_maps(404, PennylaneClient::NotFoundError)
  def test_409_is_a_conflict_error = assert_maps(409, PennylaneClient::ConflictError)
  def test_422_is_a_validation_error = assert_maps(422, PennylaneClient::ValidationError)
  def test_429_is_a_rate_limit_error = assert_maps(429, PennylaneClient::RateLimitError)
  def test_500_is_a_server_error = assert_maps(500, PennylaneClient::ServerError)
  def test_503_is_a_server_error = assert_maps(503, PennylaneClient::ServerError)
  def test_any_other_5xx_is_a_server_error = assert_maps(502, PennylaneClient::ServerError)

  def test_an_undocumented_status_falls_back_to_the_base_class
    assert_instance_of PennylaneClient::Error, error_for(418)
  end

  def test_every_class_is_a_pennylane_client_error
    [
      PennylaneClient::AuthenticationError, PennylaneClient::PermissionError, PennylaneClient::NotFoundError,
      PennylaneClient::ConflictError, PennylaneClient::ValidationError, PennylaneClient::RateLimitError,
      PennylaneClient::ServerError, PennylaneClient::ConnectionError, PennylaneClient::TimeoutError
    ].each { assert_operator _1, :<, PennylaneClient::Error }
  end

  def test_parses_the_error_message_details_shape
    body = '{"error":"unprocessable_entity","message":"Entry lines are not balanced",' \
           '"details":{"debit_total":"100.00","credit_total":"80.00"}}'
    error = error_for(422, body)

    assert_equal "422 unprocessable_entity: Entry lines are not balanced", error.message
    assert_equal "unprocessable_entity", error.code
    assert_equal({ debit_total: "100.00", credit_total: "80.00" }, error.details)
    assert_equal body, error.body
  end

  def test_parses_the_status_error_shape
    error = error_for(409, '{"status":409,"error":"A document with ID 2058167880 already exists."}')

    assert_equal "409: A document with ID 2058167880 already exists.", error.message
    assert_nil error.code
    assert_nil error.details
  end

  def test_parses_a_message_only_shape
    assert_equal "400: Bad filter", error_for(400, '{"message":"Bad filter"}').message
  end

  def test_keeps_a_plain_text_body_as_the_message
    assert_equal "503: Service Unavailable", error_for(503, "Service Unavailable\n").message
  end

  def test_survives_an_empty_or_malformed_body
    assert_equal "500", error_for(500, "").message
    assert_equal "500: {not json", error_for(500, "{not json").message
    assert_equal "500: [1, 2]", error_for(500, "[1, 2]").message
  end

  def test_truncates_a_long_plain_text_body_in_the_message
    error = error_for(502, "x" * 1_000)

    assert_operator error.message.length, :<, 300
    assert_equal 1_000, error.body.length
  end

  def test_truncates_a_long_json_message_too
    assert_operator error_for(422, { message: "y" * 1_000 }.to_json).message.length, :<, 300
  end

  def test_rate_limit_error_exposes_retry_after_in_seconds
    assert_in_delta 3.0, error_for(429, "", { "retry-after" => "3" }).retry_after
    assert_nil error_for(429).retry_after
    assert_nil error_for(429, "", { "retry-after" => "soon" }).retry_after
  end

  def test_a_connection_error_carries_no_status
    error = PennylaneClient::ConnectionError.new("connection refused")

    assert_nil error.status
    assert_equal "connection refused", error.message
  end
end
