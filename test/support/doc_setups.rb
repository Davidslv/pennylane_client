# frozen_string_literal: true

require "json"
require "openssl"
require_relative "doc_shims"

# The setups a docs example can name in its tag (DocExamples): stubs beyond
# the contract's examples, and stand-ins for the names a Rails recipe uses.
# Each returns the check to run after the example, or nil.
#
# Included in DocsExamplesTest, so the stubs and assertions are the test's.
module DocSetups
  API = "https://app.pennylane.com/api/external/v2"
  SECRET = "whsec_docs"
  NAMES = %w[validation_error unauthorized_once export_ready export_error webhook rails sidekiq rails_webhook].freeze

  def prepare(setup, sandbox)
    return nil unless setup
    raise ArgumentError, "no setup #{setup.inspect}" unless NAMES.include?(setup)

    public_send(:"setup_#{setup}", sandbox)
  end

  # The 422 from Pennylane's errors guide.
  def setup_validation_error(_sandbox)
    body = { error: "unprocessable_entity", message: "Missing required field: customer_id",
             details: { field: "customer_id", issue: "is required" } }
    stub_request(:post, "#{API}/customer_invoices").to_return(json(body).merge(status: 422))
    nil
  end

  def setup_unauthorized_once(_sandbox)
    stub_request(:get, "#{API}/me").to_return(status: 401, body: '{"error":"Unauthorized"}')
                                   .then.to_return(json(@contract.body_for(:getMe)))
    ->(_) { assert_requested :get, "#{API}/me", times: 2 }
  end

  def setup_export_ready(_sandbox)
    ready = @contract.body_for(:getFecExport).merge("status" => "ready")
    stub_request(:get, %r{#{API}/exports/fecs/\d+\z}).to_return(json(ready))
    nil
  end

  def setup_export_error(_sandbox)
    failed = @contract.body_for(:getGeneralLedgerExport).merge("status" => "error")
    stub_request(:get, %r{#{API}/exports/general_ledgers/\d+\z}).to_return(json(failed))
    nil
  end

  def setup_webhook(sandbox)
    ENV["PENNYLANE_WEBHOOK_SECRET"] = SECRET
    sandbox.let(:raw_body, delivery)
    sandbox.let(:signature, signed(delivery))
    nil
  end

  def setup_rails(sandbox)
    rails_shims(sandbox)
    nil
  end

  def setup_sidekiq(sandbox)
    rails_shims(sandbox)
    sandbox.const_set(:Sidekiq, DocShims::Sidekiq)
    lambda do |box|
      assert_kind_of Hash, box::FinalizeInvoiceJob.new.perform(42)
      assert_requested :put, "#{API}/customer_invoices/42/finalize"
    end
  end

  def setup_rails_webhook(sandbox)
    ENV["PENNYLANE_WEBHOOK_SECRET"] = SECRET
    %i[ApplicationController ActiveRecord PennylaneDelivery PennylaneEventJob].each do |name|
      sandbox.const_set(name, DocShims.const_get(name))
    end
    DocShims::PennylaneDelivery.ids.clear
    DocShims::PennylaneEventJob.enqueued.clear
    ->(box) { check_webhook_controller(box::PennylaneWebhooksController) }
  end

  private

  # The same delivery twice, then a forged one: one job, and a 400.
  def check_webhook_controller(controller)
    statuses = [delivery, delivery, "{}"].map { answer(controller, signed_over: _1) }
    job = ["customer_invoice.e_invoicing_status_updated", JSON.parse(delivery, symbolize_names: true)[:data]]

    assert_equal(%i[ok ok bad_request], statuses)
    assert_equal([job], DocShims::PennylaneEventJob.enqueued)
  end

  # The controller's answer to the delivery, with a signature over
  # `signed_over`: the delivery itself, or something forged.
  def answer(controller, signed_over:)
    request = DocShims::Request.new(delivery, { "X-Pennylane-Signature" => signed(signed_over) })
    controller.new(request).tap(&:create).status
  end

  def rails_shims(sandbox)
    sandbox.const_set(:Rails, DocShims::Rails)
    sandbox.const_set(:ActiveSupport, DocShims::ActiveSupport)
  end

  def json(body) = { status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(body) }

  def signed(body, at: Time.now.to_i)
    "t=#{at},v1=#{OpenSSL::HMAC.hexdigest("SHA256", SECRET, "#{at}.#{body}")}"
  end

  # The delivery from Pennylane's webhook guide.
  def delivery
    JSON.generate({ id: 987_654, event: "customer_invoice.e_invoicing_status_updated", retry_count: 0,
                    created: 1_782_864_000,
                    data: { context: { company_id: "abc-123", firm_id: "firm-456" },
                            object: { id: 42, e_invoicing: { status: "accepted" } },
                            previous_attributes: { e_invoicing: { status: "submitted" } } } })
  end
end
