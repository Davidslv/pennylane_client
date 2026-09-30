# frozen_string_literal: true

require "test_helper"
require "openssl"
require "minitest/mock"

# Vectors built by hand from the documented scheme
# (docs/api/contract/<date>/guides/webhooks-receiving-and-verifying.md):
# `X-Pennylane-Signature: t=<unix seconds>,v1=<hex>`, where v1 is
# HMAC-SHA256 of "{t}.{raw_body}" keyed with the subscription secret.
module WebhookVectors
  SECRET = "whsec_test_secret"
  NOW = 1_782_864_000
  BODY = <<~JSON.chomp
    {"id":987654,"event":"customer_invoice.e_invoicing_status_updated","retry_count":0,"created":1782864000,"data":{"context":{"company_id":"abc-123","firm_id":"firm-456"},"object":{"id":42,"e_invoicing":{"status":"accepted"}}}}
  JSON

  def sign(body = BODY, at: NOW, secret: SECRET)
    "t=#{at},v1=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "#{at}.#{body}")}"
  end

  def digest = sign.split("v1=").last

  def verify(body = BODY, header = sign, secret: SECRET, now: NOW, **)
    PennylaneClient::Webhook.verify!(body, header, secret:, now:, **)
  end

  def assert_rejected(message, &)
    error = assert_raises(PennylaneClient::SignatureError, &)
    assert_match message, error.message
  end
end

class WebhookTest < Minitest::Test
  include WebhookVectors

  def test_a_valid_delivery_returns_the_event
    event = verify

    assert_equal 987_654, event[:id]
    assert_equal "customer_invoice.e_invoicing_status_updated", event[:event]
    assert_equal "accepted", event.dig(:data, :object, :e_invoicing, :status)
  end

  # A literal vector, so a change to how the signed string is built fails
  # here even if the `sign` helper changes with it.
  def test_a_fixed_vector_verifies
    header = "t=1782864000,v1=0b5f56510ee62370106bc74036198c6f9076a048d31c6fccb594642ec5f3201f"

    assert_equal "dms_file.created", verify('{"id":1,"event":"dms_file.created"}', header)[:event]
  end

  def test_the_event_is_deep_frozen
    event = verify

    assert_predicate event, :frozen?
    assert_predicate event[:data][:object], :frozen?
    assert_predicate event[:event], :frozen?
  end

  def test_a_tampered_body_is_rejected
    assert_rejected(/does not match/) { verify(BODY.sub("accepted", "rejected"), sign) }
  end

  def test_a_tampered_timestamp_is_rejected
    assert_rejected(/does not match/) { verify(BODY, sign.sub("t=#{NOW}", "t=#{NOW + 1}")) }
  end

  def test_a_wrong_secret_is_rejected
    assert_rejected(/does not match/) { verify(BODY, sign(secret: "another_secret")) }
  end

  def test_a_binary_body_is_verified_on_its_bytes
    body = BODY.sub("abc-123", "société").b

    assert_equal "société", verify(body, sign(body)).dig(:data, :context, :company_id)
  end

  def test_a_signed_body_that_is_not_a_json_object_is_rejected
    assert_rejected(/JSON/) { verify("not json", sign("not json")) }
    assert_rejected(/JSON/) { verify("[1]", sign("[1]")) }
  end

  def test_a_blank_or_non_string_secret_is_an_argument_error
    assert_raises(ArgumentError) { verify(BODY, sign, secret: "") }
    assert_raises(ArgumentError) { verify(BODY, sign, secret: nil) }
    assert_raises(ArgumentError) { verify(BODY, sign, secret: 5) }
  end

  def test_the_error_never_carries_the_secret_or_the_expected_digest
    error = assert_raises(PennylaneClient::SignatureError) { verify(BODY, sign(secret: "another_secret")) }

    refute_includes error.message, SECRET
    refute_includes error.message, digest
  end

  def test_the_comparison_is_constant_time
    calls = []
    compare = OpenSSL.method(:fixed_length_secure_compare)
    spy = lambda do |a, b|
      calls << [a.bytesize, b.bytesize]
      compare.call(a, b)
    end

    OpenSSL.stub(:fixed_length_secure_compare, spy) { verify }
    OpenSSL.stub(:fixed_length_secure_compare, spy) { assert_raises(PennylaneClient::SignatureError) { verify(BODY, sign(secret: "x")) } }

    assert_equal [[64, 64], [64, 64]], calls
  end

  def test_signature_error_is_a_pennylane_client_error
    assert_operator PennylaneClient::SignatureError, :<, PennylaneClient::Error
  end
end

class WebhookHeaderTest < Minitest::Test
  include WebhookVectors

  def test_a_stale_timestamp_is_rejected
    assert_rejected(/tolerance/) { verify(BODY, sign(at: NOW - 301)) }
  end

  def test_a_timestamp_inside_the_tolerance_is_accepted
    assert_equal 987_654, verify(BODY, sign(at: NOW - 300))[:id]
  end

  def test_a_timestamp_from_the_future_is_rejected
    assert_rejected(/tolerance/) { verify(BODY, sign(at: NOW + 301)) }
  end

  def test_the_tolerance_can_be_widened
    assert_equal 987_654, verify(BODY, sign(at: NOW - 3_600), tolerance: 3_600)[:id]
  end

  def test_a_nil_tolerance_skips_the_age_check
    assert_equal 987_654, verify(BODY, sign(at: NOW - 86_400), tolerance: nil)[:id]
  end

  def test_the_age_is_checked_only_after_the_signature
    assert_rejected(/does not match/) { verify(BODY, sign(at: NOW - 301, secret: "another_secret")) }
  end

  def test_now_defaults_to_the_wall_clock
    fresh = Time.now.to_i

    assert_equal 987_654, PennylaneClient::Webhook.verify!(BODY, sign(at: fresh), secret: SECRET)[:id]
  end

  def test_now_can_be_a_time
    assert_equal 987_654, verify(BODY, sign, now: Time.at(NOW + 10))[:id]
  end

  def test_t_is_signed_as_sent
    assert_equal 987_654, verify(BODY, sign(at: "0#{NOW}"))[:id]
  end

  def test_a_missing_header_is_rejected
    assert_rejected(/missing/) { verify(BODY, nil) }
    assert_rejected(/missing/) { verify(BODY, "  ") }
    assert_rejected(/missing/) { verify(BODY, 123) }
    assert_rejected(/missing/) { verify(BODY, ["t=1"]) }
  end

  def test_a_header_in_a_hostile_encoding_is_rejected
    assert_rejected(/malformed/) { verify(BODY, "\xff,t=1".dup.force_encoding(Encoding::UTF_8)) }
    assert_rejected(/malformed/) { verify(BODY, "t=1,v1=00".encode(Encoding::UTF_16LE)) }
  end

  def test_malformed_headers_are_rejected
    ["garbage", "t", ",", "v1=#{digest}", "t=#{NOW}", "t=#{NOW},v1=", "t=,v1=#{digest}", "t=soon,v1=#{digest}",
     "t=#{NOW}.5,v1=#{digest}", "t=#{NOW},v1=#{digest[0..-3]}", "t=#{NOW},v1=#{"z" * 64}"].each do |header|
      assert_rejected(/malformed/) { verify(BODY, header) }
    end
  end

  def test_whitespace_around_the_parts_is_tolerated
    assert_equal 987_654, verify(BODY, sign.split(",").join(", "))[:id]
  end

  def test_any_one_matching_v1_is_enough
    assert_equal 987_654, verify(BODY, "t=#{NOW},v1=#{"0" * 64},v1=#{digest}")[:id]
  end

  def test_the_v1_comparison_ignores_hex_case
    assert_equal 987_654, verify(BODY, "t=#{NOW},v1=#{digest.upcase}")[:id]
  end
end
