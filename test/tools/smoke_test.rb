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

  def operations
    [op(:getMe, :get, "/me"),
     op(:getCustomers, :get, "/customers", paginated: true),
     op(:getCustomer, :get, "/customers/{id}"),
     op(:getTrialBalance, :get, "/trial_balance"),
     op(:getOldThings, :get, "/old_things", deprecated: true),
     op(:postCustomerContact, :post, "/customers/{customer_id}/contacts")]
  end

  def record(id, method, path, required_query: [])
    { "operation_id" => id, "method" => method, "path" => "/api/external/v2#{path}", "tags" => ["T"],
      "deprecated" => id == "getOldThings",
      "parameters" => required_query.map { { "in" => "query", "name" => _1, "required" => true } } }
  end

  def document
    { "retrieved_on" => "2026-09-30",
      "operations" => [record("getMe", "GET", "/me"), record("getCustomers", "GET", "/customers"),
                       record("getCustomer", "GET", "/customers/{id}"),
                       record("getTrialBalance", "GET", "/trial_balance", required_query: %w[period_start]),
                       record("getOldThings", "GET", "/old_things"),
                       record("postCustomerContact", "POST", "/customers/{customer_id}/contacts")] }
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

  # Answers each operation from `answers` (a value, or an Exception to
  # raise) and records every call.
  class FakeClient
    attr_reader :calls

    def initialize(answers)
      @answers = answers
      @calls = []
    end

    def call(operation_id, body = nil, **params)
      @calls << [operation_id, body, params]
      answer = @answers.fetch(operation_id) { raise "unexpected call #{operation_id}" }
      raise answer if answer.is_a?(Exception)

      answer
    end
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
    assert_equal %i[getMe getCustomers], plan.lists.map(&:id)
  end

  def test_finds_the_detail_read_for_a_list
    assert_equal :getCustomer, plan.detail(plan.lists.last).id
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
    results, calls = reads({ getMe: { id: 1 }, getCustomers: { items: [], has_more: false } })

    assert_equal({ "getMe" => "pass", "getCustomers" => "pass" }, results)
    assert_equal [[:getMe, nil, {}], [:getCustomers, nil, { limit: 1 }]], calls
  end

  def test_follows_the_first_listed_item_to_its_detail_read
    results, calls = reads({ getMe: {}, getCustomers: { items: [{ id: 7 }] }, getCustomer: { id: 7 } })

    assert_equal "pass", results["getCustomer"]
    assert_includes calls, [:getCustomer, nil, { id: 7 }]
  end

  def test_a_missing_scope_is_not_run_and_an_error_fails_without_the_response_body
    results, = reads({ getMe: error(PennylaneClient::PermissionError, 403),
                       getCustomers: error(PennylaneClient::ServerError, 500) })

    assert_equal "not run: 403 PermissionError", results["getMe"]
    assert_equal "fail: 500 ServerError", results["getCustomers"]
  end

  def test_waits_before_every_request_to_stay_well_inside_the_rate_limit
    sleeps = []
    reads({ getMe: {}, getCustomers: { items: [{ id: 7 }] }, getCustomer: {} }, sleeps: sleeps)

    assert_equal [Smoke::PACE] * 3, sleeps
    assert_operator 5 / Smoke::PACE, :<=, 10
  end

  def test_never_sends_a_write
    _, calls = reads({ getMe: {}, getCustomers: { items: [{ id: 7 }] }, getCustomer: {} })

    assert(calls.all? { |(id, _, _)| id.start_with?("get") })
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
      assert_includes markdown, "| Live-verified | 1 of 5 live |"
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

      assert_equal 0, main(root, { getMe: {}, getCustomers: { items: [] } }, out: out)
      assert_path_exists File.join(root, "docs/api/live/2026-10-01-octocat.json")
      assert_match(/2 passed, 0 failed, 0 not run/, out.string)
    end
  end

  def test_main_exits_one_when_a_read_fails
    with_root do |root|
      assert_equal 1, main(root, { getMe: error(PennylaneClient::ServerError, 500), getCustomers: { items: [] } })
    end
  end
end
