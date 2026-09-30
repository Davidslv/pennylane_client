# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tools/smoke"
require_relative "../../tools/checklist"
require "open3"
require "rbconfig"
require "stringio"
require "tmpdir"

module SmokeFixtures
  Op = PennylaneClient::Operation

  def op(id, verb, path, paginated: false, deprecated: false)
    Op.new(id: id, verb: verb, path: "/api/external/v2#{path}", paginated: paginated,
           max_limit: paginated ? 100 : nil, body: nil, success: 200, deprecated: deprecated)
  end

  CONTACTS = "/customers/{customer_id}/contacts"
  HOOKS = "/webhook_subscriptions"

  def operations
    [op(:getMe, :get, "/me"), op(:getCustomers, :get, "/customers", paginated: true),
     op(:getCustomer, :get, "/customers/{id}"), op(:getTrialBalance, :get, "/trial_balance"),
     op(:getOldThings, :get, "/old_things", deprecated: true),
     op(:getWebhookSubscriptions, :get, HOOKS), op(:getWebhookSubscription, :get, "#{HOOKS}/{id}"),
     op(:postWebhookSubscriptions, :post, HOOKS), op(:putWebhookSubscription, :put, "#{HOOKS}/{id}"),
     op(:deleteWebhookSubscription, :delete, "#{HOOKS}/{id}"),
     op(:getCustomerContacts, :get, CONTACTS, paginated: true), op(:postCustomerContact, :post, CONTACTS),
     op(:getCustomerContact, :get, "#{CONTACTS}/{id}"), op(:putCustomerContact, :put, "#{CONTACTS}/{id}"),
     op(:deleteCustomerContact, :delete, "#{CONTACTS}/{id}")]
  end

  # The snapshot records for `operations`; only getTrialBalance has a
  # required query param.
  def document
    required = [{ "in" => "query", "name" => "period_start", "required" => true }]
    records = operations.map do |operation|
      query = operation.id == :getTrialBalance ? required : []
      { "operation_id" => operation.id.to_s, "method" => operation.verb.to_s.upcase, "path" => operation.path,
        "tags" => ["T"], "deprecated" => operation.deprecated, "parameters" => query }
    end
    { "retrieved_on" => "2026-09-30", "operations" => records }
  end

  # Answers for a clean run of the reads: one customer, no webhook.
  def read_answers
    { getMe: {}, getCustomers: { items: [{ id: 7 }] }, getCustomer: { id: 7 }, getWebhookSubscriptions: { items: [] } }
  end

  def plan = Smoke::Plan.new(operations, document)

  # A throwaway repo holding the snapshot above and a README with the markers.
  def with_root
    Dir.mktmpdir do |root|
      dir = File.join(root, "docs/api/contract/2026-09-30")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "operations.json"), JSON.generate(document))
      yield root
    end
  end

  def error(klass, status)
    klass.new(nil, status: status, body: %({"message":"secret detail about customer 42"}))
  end

  # Answers each operation from `answers` (a value, an Exception to raise,
  # or a Proc given the params) and records every call.
  class FakeClient
    attr_reader :calls

    def initialize(answers)
      @answers = answers
      @calls = []
    end

    def call(operation_id, body = nil, **params)
      @calls << [operation_id, body, params]
      answer = @answers.fetch(operation_id) { raise "unexpected call #{operation_id}" }
      answer = answer.call(params) if answer.is_a?(Proc)
      raise answer if answer.is_a?(Exception)

      answer
    end

    def paginate(operation_id, **params) = call(operation_id, **params).fetch(:items).lazy

    def ids = calls.map(&:first)
  end
end

class SmokeSkipTest < Minitest::Test
  include SmokeFixtures

  def test_without_a_token_it_skips_and_exits_zero
    out = StringIO.new

    assert_equal 0, Smoke.main(env: {}, root: "unused", out: out)
    assert_match(/Skipping rake smoke: set PENNYLANE_SMOKE_TOKEN/, out.string)
  end

  def test_the_script_itself_skips_and_exits_zero_without_a_token
    root = File.expand_path("../..", __dir__)
    output, status = Open3.capture2e({ "PENNYLANE_SMOKE_TOKEN" => nil }, RbConfig.ruby, "tools/smoke.rb", chdir: root)

    assert_predicate status, :success?, output
    assert_match(/Skipping rake smoke/, output)
  end

  def test_with_a_token_but_no_github_user_it_refuses_before_any_request
    client = FakeClient.new({})
    out = StringIO.new

    assert_equal 1, Smoke.main(env: { "PENNYLANE_SMOKE_TOKEN" => "t" }, root: "unused", out: out, client: client)
    assert_match(/PENNYLANE_SMOKE_GITHUB_USER/, out.string)
    assert_empty client.calls
  end
end

class SmokePlanTest < Minitest::Test
  include SmokeFixtures

  def test_reads_every_live_get_without_path_or_required_query_params
    assert_equal %i[getMe getCustomers getWebhookSubscriptions], plan.lists.map(&:id)
  end

  def test_finds_the_detail_read_for_a_list
    assert_equal :getCustomer, plan.detail(plan.lists[1]).id
    assert_nil plan.detail(plan.lists.first)
  end
end

class SmokeReadsTest < Minitest::Test
  include SmokeFixtures

  def reads(answers, sleeps: [])
    client = FakeClient.new(answers)
    results = Smoke::Runner.new(client: client, plan: plan, sleeper: ->(seconds) { sleeps << seconds }).reads
    [results, client.calls]
  end

  def test_each_read_that_answers_passes_and_a_list_asks_for_one_item
    results, calls = reads(read_answers.merge(getCustomers: { items: [], has_more: false }))

    assert_equal({ "getMe" => "pass", "getCustomers" => "pass", "getWebhookSubscriptions" => "pass" }, results)
    assert_equal [[:getMe, nil, {}], [:getCustomers, nil, { limit: 1 }], [:getWebhookSubscriptions, nil, {}]], calls
  end

  def test_follows_the_first_listed_item_to_its_detail_read
    results, calls = reads(read_answers)

    assert_equal "pass", results["getCustomer"]
    assert_includes calls, [:getCustomer, nil, { id: 7 }]
  end

  def test_a_missing_scope_is_not_run_and_an_error_fails_without_the_response_body
    results, = reads(read_answers.merge(getMe: error(PennylaneClient::PermissionError, 403),
                                        getCustomers: error(PennylaneClient::ServerError, 500)))

    assert_equal "not run: 403 PermissionError", results["getMe"]
    assert_equal "fail: 500 ServerError", results["getCustomers"]
  end

  def test_waits_before_every_request_to_stay_well_inside_the_rate_limit
    sleeps = []
    reads(read_answers, sleeps: sleeps)

    assert_equal [Smoke::PACE] * 4, sleeps
    assert_operator 5 / Smoke::PACE, :<=, 10
  end

  def test_never_sends_a_write
    _, calls = reads(read_answers)

    assert(calls.all? { |(id, _, _)| id.start_with?("get") })
  end
end

class SmokeWritesTest < Minitest::Test
  include SmokeFixtures

  def write_answers
    read_answers.merge(postCustomerContact: { id: 90 }, getCustomerContact: { id: 90 }, putCustomerContact: {},
                       deleteCustomerContact: true, postWebhookSubscriptions: { id: 5, secret: "whsec" },
                       getWebhookSubscription: { id: 5 }, putWebhookSubscription: {}, deleteWebhookSubscription: true)
  end

  def run_writes(answers)
    client = FakeClient.new(answers)
    runner = Smoke::Runner.new(client: client, plan: plan, sleeper: ->(_) {})
    runner.reads
    [runner.writes, client]
  end

  CONTACT_STEPS = %i[postCustomerContact getCustomerContact putCustomerContact deleteCustomerContact].freeze
  HOOK_STEPS = %i[postWebhookSubscriptions getWebhookSubscription putWebhookSubscription
                  deleteWebhookSubscription].freeze

  def test_creates_reads_updates_and_deletes_a_contact_on_the_first_customer
    results, client = run_writes(write_answers)
    calls = client.calls.select { CONTACT_STEPS.include?(_1.first) }

    assert_equal CONTACT_STEPS, calls.map(&:first)
    assert_equal(%w[pass] * 4, results.values_at(*CONTACT_STEPS.map(&:to_s)))
  end

  def test_the_contact_is_on_the_first_customer_with_a_unique_address_and_the_id_pennylane_gave
    _, client = run_writes(write_answers)
    create, *rest = client.calls.select { CONTACT_STEPS.include?(_1.first) }.map(&:last)

    assert_equal 7, create[:customer_id]
    assert_match(/\Asmoke\+\h+@example\.com\z/, create[:email])
    assert(rest.all? { _1.values_at(:customer_id, :id) == [7, 90] })
  end

  def test_deletes_the_contact_even_when_a_step_in_between_fails
    results, client = run_writes(write_answers.merge(getCustomerContact: error(PennylaneClient::ServerError, 500)))

    assert_equal "fail: 500 ServerError", results["getCustomerContact"]
    assert_includes client.ids, :deleteCustomerContact
  end

  def test_deletes_the_contact_even_when_the_run_is_interrupted
    client = FakeClient.new(write_answers.merge(putCustomerContact: Interrupt.new))
    runner = Smoke::Runner.new(client: client, plan: plan, sleeper: ->(_) {})
    runner.reads

    assert_raises(Interrupt) { runner.writes }
    assert_includes client.ids, :deleteCustomerContact
  end

  def test_a_failed_create_sends_nothing_after_it
    results, client = run_writes(write_answers.merge(postCustomerContact: error(PennylaneClient::ValidationError, 422)))

    assert_equal "fail: 422 ValidationError", results["postCustomerContact"]
    refute_includes client.ids, :deleteCustomerContact
  end

  def test_no_customer_means_no_contact_writes
    _, client = run_writes(write_answers.merge(getCustomers: { items: [] }))

    refute_includes client.ids, :postCustomerContact
  end

  def test_a_webhook_subscription_is_created_disabled_updated_and_deleted_when_the_company_has_none
    results, client = run_writes(write_answers)
    create = client.calls.find { _1.first == :postWebhookSubscriptions }.last

    assert_equal false, create[:enabled]
    assert_equal HOOK_STEPS, client.ids.grep(/\A#{Regexp.union(HOOK_STEPS.map(&:to_s))}\z/)
    assert_equal "pass", results["deleteWebhookSubscription"]
  end

  def test_an_existing_webhook_subscription_is_never_touched
    _, client = run_writes(write_answers.merge(getWebhookSubscriptions: { items: [{ id: 1 }] }))

    refute_includes client.ids, :postWebhookSubscriptions
    refute_includes client.ids, :putWebhookSubscription
    refute_includes client.ids, :deleteWebhookSubscription
  end
end

class SmokeWebhookCheckTest < Minitest::Test
  BODY = %({"id":"evt_1","event":"dms_file.created"})

  def check(secret: "whsec", signed_with: "whsec")
    Dir.mktmpdir do |dir|
      body = File.join(dir, "delivery.json")
      File.binwrite(body, BODY)
      signature = "t=1700000000,v1=#{OpenSSL::HMAC.hexdigest("SHA256", signed_with, "1700000000.#{BODY}")}"
      Smoke::Checks.webhook_signature({ "PENNYLANE_SMOKE_WEBHOOK_BODY" => body,
                                        "PENNYLANE_SMOKE_WEBHOOK_SIGNATURE" => signature,
                                        "PENNYLANE_SMOKE_WEBHOOK_SECRET" => secret })
    end
  end

  def test_not_run_without_a_captured_delivery
    assert_equal "not run", Smoke::Checks.webhook_signature({})
  end

  def test_a_captured_delivery_that_verifies_passes_whatever_its_age
    assert_equal "pass", check
  end

  def test_a_delivery_that_does_not_verify_fails_without_quoting_the_secret
    result = check(signed_with: "other")

    assert_equal "fail: signature does not match", result
  end

  def test_an_unreadable_body_file_is_not_run
    env = { "PENNYLANE_SMOKE_WEBHOOK_BODY" => "/nonexistent/delivery.json",
            "PENNYLANE_SMOKE_WEBHOOK_SIGNATURE" => "t=1,v1=#{"a" * 64}", "PENNYLANE_SMOKE_WEBHOOK_SECRET" => "s" }

    assert_equal "not run: cannot read PENNYLANE_SMOKE_WEBHOOK_BODY", Smoke::Checks.webhook_signature(env)
  end
end

class SmokeRateLimitProbeTest < Minitest::Test
  include SmokeFixtures

  def limited = PennylaneClient::RateLimitError.new(nil, status: 429, headers: { "retry-after" => "2" })

  # getMe answers `burst` times, then answers 429.
  def burst_then_limited(burst)
    count = 0
    ->(_) { (count += 1) > burst ? limited : {} }
  end

  def probe(probe_answers, reader_answers, customer_id: 7)
    probe = FakeClient.new(probe_answers)
    reader = FakeClient.new(reader_answers)
    sleeps = []
    result = Smoke::RateLimitProbe.new(client: probe, reader: reader, customer_id: customer_id,
                                       sleeper: ->(seconds) { sleeps << seconds }).run
    [result, probe, reader, sleeps]
  end

  def test_passes_when_the_rate_limited_write_left_no_contact_behind
    result, probe, reader, sleeps = probe({ getMe: burst_then_limited(3), postCustomerContact: limited },
                                          { getCustomerContacts: { items: [{ id: 1, email: "jane@example.com" }] } })

    assert_equal "pass", result
    assert_equal 4, probe.ids.count(:getMe)
    assert_equal [3.0], sleeps
    assert_equal [:getCustomerContacts], reader.ids
  end

  def test_fails_and_cleans_up_when_the_rate_limited_write_was_executed
    probe = FakeClient.new({ getMe: burst_then_limited(0), postCustomerContact: limited })
    leaked = ->(_) { { items: [{ id: 55, email: probe.calls.last.last[:email] }] } }
    reader = FakeClient.new({ getCustomerContacts: leaked, deleteCustomerContact: true })

    result = Smoke::RateLimitProbe.new(client: probe, reader: reader, customer_id: 7, sleeper: ->(_) {}).run

    assert_equal "fail: the rate-limited write was executed", result
    assert_includes reader.calls, [:deleteCustomerContact, nil, { customer_id: 7, id: 55 }]
  end

  def test_the_probe_contact_has_its_own_unique_address
    probe_client = probe({ getMe: burst_then_limited(0), postCustomerContact: limited },
                         { getCustomerContacts: { items: [] } })[1]

    assert_match(/\Asmoke-429\+\h+@example\.com\z/, probe_client.calls.last.last[:email])
  end

  def test_not_run_when_the_burst_never_hits_the_limit
    result, probe, = probe({ getMe: {} }, {})

    assert_equal "not run: no 429 within #{Smoke::RateLimitProbe::BURST} requests", result
    refute_includes probe.ids, :postCustomerContact
  end

  def test_not_run_and_cleaned_up_when_the_write_was_not_rate_limited
    result, _, reader, = probe({ getMe: burst_then_limited(0), postCustomerContact: { id: 60 } },
                               { deleteCustomerContact: true })

    assert_equal "not run: the write was not rate-limited", result
    assert_equal [[:deleteCustomerContact, nil, { customer_id: 7, id: 60 }]], reader.calls
  end

  def test_the_probe_client_neither_waits_on_its_own_limit_nor_retries_when_rate_limited
    stub = stub_request(:get, "https://app.pennylane.com/api/external/v2/me")
           .to_return({ status: 200, body: "{}" }.freeze).times(Smoke::RateLimitProbe::BURST)
           .then.to_return(status: 429, headers: { "retry-after" => "2" }, body: "")
    client = Smoke.probe_client("probe-token")

    Smoke::RateLimitProbe::BURST.times { client.call(:getMe) }

    assert_raises(PennylaneClient::RateLimitError) { client.call(:getMe) }
    assert_requested stub, times: Smoke::RateLimitProbe::BURST + 1
  end

  def test_not_run_without_a_customer
    result, probe, = probe({}, {}, customer_id: nil)

    assert_equal "not run: no customer in the sandbox", result
    assert_empty probe.calls
  end
end

class SmokeReportTest < Minitest::Test
  include SmokeFixtures

  def test_a_report_round_trips_into_the_checklist
    with_root do |root|
      Smoke::Report.write(root: root, date: Date.new(2026, 10, 1), user: "octocat", contract: "2026-09-30",
                          operations: { "getMe" => "pass", "getCustomers" => "fail: 500 ServerError" }, checks: {})
      markdown = Checklist.generate(root: root, registered: %w[getMe getCustomers])

      assert_includes markdown, "| `getMe` | GET | `/me` | yes | no | sandbox-verified 2026-10-01 (by @octocat) |"
      assert_includes markdown, "| `getCustomers` | GET | `/customers` | yes | no | unverified: no sandbox access |"
      assert_includes markdown, "| Live-verified | 1 of #{operations.count { !_1.deprecated }} live |"
    end
  end

  def test_the_report_is_named_by_date_and_user_and_records_the_gem_and_contract
    with_root do |root|
      path = Smoke::Report.write(root: root, date: Date.new(2026, 10, 1), user: "octocat", contract: "2026-09-30",
                                 operations: { "getMe" => "pass" }, checks: { "webhook_signature" => "not run" })
      report = JSON.parse(File.read(path))

      assert_equal File.join(root, "docs/api/live/2026-10-01-octocat.json"), path
      assert_equal PennylaneClient::VERSION, report["gem_version"]
      assert_equal "2026-09-30", report["contract"]
      assert_equal({ "webhook_signature" => "not run" }, report["checks"])
    end
  end

  ENV_OK = { "PENNYLANE_SMOKE_TOKEN" => "t", "PENNYLANE_SMOKE_GITHUB_USER" => "octocat" }.freeze

  def main(root, answers, out: StringIO.new, env: ENV_OK)
    Smoke.main(env: env, root: root, out: out, client: FakeClient.new(answers), operations: operations,
               today: Date.new(2026, 10, 1), sleeper: ->(_) {})
  end

  def test_main_runs_the_reads_and_writes_the_report
    with_root do |root|
      out = StringIO.new

      assert_equal 0, main(root, read_answers, out: out)
      assert_path_exists File.join(root, "docs/api/live/2026-10-01-octocat.json")
      assert_match(/4 passed, 0 failed, 0 not run/, out.string)
    end
  end

  def test_main_sends_no_write_unless_the_contributor_says_the_token_is_for_a_sandbox
    with_root do |root|
      out = StringIO.new
      main(root, read_answers, out: out)
      report = JSON.parse(File.read(File.join(root, "docs/api/live/2026-10-01-octocat.json")))

      assert_match(/PENNYLANE_SMOKE_SANDBOX=yes/, out.string)
      assert(report["operations"].keys.all? { _1.start_with?("get") })
    end
  end

  def test_main_runs_the_writes_on_a_sandbox
    with_root do |root|
      answers = read_answers.merge(postCustomerContact: { id: 90 }, getCustomerContact: {}, putCustomerContact: {},
                                   deleteCustomerContact: true, postWebhookSubscriptions: { id: 5 },
                                   getWebhookSubscription: {}, putWebhookSubscription: {},
                                   deleteWebhookSubscription: true)
      main(root, answers, env: ENV_OK.merge("PENNYLANE_SMOKE_SANDBOX" => "yes"))
      report = JSON.parse(File.read(File.join(root, "docs/api/live/2026-10-01-octocat.json")))

      assert_equal "pass", report["operations"]["deleteCustomerContact"]
    end
  end

  def test_main_records_the_checks_and_probes_only_when_asked_on_a_sandbox
    with_root do |root|
      main(root, read_answers)
      report = JSON.parse(File.read(File.join(root, "docs/api/live/2026-10-01-octocat.json")))

      assert_equal({ "rate_limited_write_not_executed" => "not run: set PENNYLANE_SMOKE_SANDBOX=yes and " \
                                                          "PENNYLANE_SMOKE_PROBE_429=yes to probe",
                     "webhook_signature" => "not run" }, report["checks"])
    end
  end

  def test_main_exits_one_when_a_read_fails
    with_root do |root|
      assert_equal 1, main(root, read_answers.merge(getMe: error(PennylaneClient::ServerError, 500)))
    end
  end
end
