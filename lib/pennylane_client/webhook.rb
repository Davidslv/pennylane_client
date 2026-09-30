# frozen_string_literal: true

require "json"
require "openssl"

module PennylaneClient
  # Verifies an inbound webhook delivery. Pennylane signs each POST with
  # `X-Pennylane-Signature: t=<unix seconds>,v1=<hex>`, where v1 is
  # HMAC-SHA256 of "{t}.{raw_body}" keyed with the subscription secret
  # (docs/api/contract/<date>/guides/webhooks-receiving-and-verifying.md).
  #
  #   event = PennylaneClient::Webhook.verify!(request.raw_post,
  #                                            request.headers["X-Pennylane-Signature"],
  #                                            secret: ENV.fetch("PENNYLANE_WEBHOOK_SECRET"))
  #   event[:id]    # the delivery id: de-duplicate on it
  #   event[:event] # "customer_invoice.e_invoicing_status_updated"
  #
  # Delivery is at-least-once and unordered. The caller de-duplicates on
  # `event[:id]`.
  module Webhook
    HEADER = "X-Pennylane-Signature"
    DEFAULT_TOLERANCE = 300
    TIMESTAMP = /\A\d+\z/
    DIGEST_HEX = /\A\h{64}\z/

    module_function

    # Returns the event as a deep-frozen Hash with symbol keys. Raises
    # SignatureError when the header is missing or malformed, when no v1
    # matches, when `t` is more than `tolerance` seconds from `now` (either
    # way; nil skips the check), or when the body is not a JSON object.
    # `raw_body` must be the bytes as received, before any JSON parsing.
    # A blank or non-String secret is an ArgumentError: a bug in the caller,
    # not a bad delivery. `now` is a Time or Unix seconds.
    def verify!(raw_body, signature_header, secret:, tolerance: DEFAULT_TOLERANCE, now: Time.now)
      raise ArgumentError, "secret must be a non-empty String" unless secret.is_a?(String) && !secret.empty?

      timestamp, signatures = parse(signature_header)
      authenticate(raw_body, timestamp, signatures, secret)
      if tolerance && (now.to_i - Integer(timestamp, 10)).abs > tolerance
        raise SignatureError, "timestamp is outside the #{tolerance} second tolerance"
      end

      event(raw_body)
    end

    # [t, [v1, ...]] from "t=1657875952,v1=5257a8...", both as sent: the
    # HMAC covers `t` exactly as signed. Every v1 is kept, so a header
    # carrying more than one matches on any of them. The header comes from
    # anyone, so it is read as bytes and never raises anything but
    # SignatureError.
    def parse(header)
      values = fields(header)
      timestamp = values.fetch("t", []).first.to_s
      signatures = values.fetch("v1", []).map(&:downcase).grep(DIGEST_HEX)
      raise SignatureError, "#{HEADER} header is malformed" unless timestamp.match?(TIMESTAMP) && signatures.any?

      [timestamp, signatures]
    end

    # {"t" => ["1657875952"], "v1" => ["5257a8...", ...]}, read as bytes.
    def fields(header)
      header = header.b.strip if header.is_a?(String)
      raise SignatureError, "#{HEADER} header is missing" if !header.is_a?(String) || header.empty?

      header.split(",").each_with_object({}) do |part, values|
        name, value = part.strip.split("=", 2)
        (values[name] ||= []) << value if value
      end
    end

    # Each comparison is fixed-length and constant-time: `signatures` holds
    # only 64-character hex strings, the length of a SHA-256 hexdigest.
    def authenticate(raw_body, timestamp, signatures, secret)
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.".b + raw_body.to_s.b)
      return if signatures.any? { OpenSSL.fixed_length_secure_compare(expected, _1) }

      raise SignatureError, "signature does not match"
    end

    def event(raw_body)
      parsed = JSON.parse(raw_body.to_s.dup.force_encoding(Encoding::UTF_8), symbolize_names: true, freeze: true)
      raise SignatureError, "body is not a JSON object" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError
      raise SignatureError, "body is not valid JSON"
    end
    private_class_method :parse, :fields, :authenticate, :event
  end
end
