# frozen_string_literal: true

# Verify the gem against a real Pennylane sandbox and write a report that
# `rake checklist` reads into the live column.
#
# Why: the maintainer has no Pennylane account, so the checklist's live
# column can only become true when someone who has one runs this. One
# command, one report file, one pull request.
#
# Credential-gated: without PENNYLANE_SMOKE_TOKEN it says why it skipped and
# exits 0. It is never part of `bundle exec rake`. It waits PACE seconds
# before every request, well inside Pennylane's 25 per 5 seconds, and never
# sends load (AGENTS.md rule 7). The report holds operationIds, results and
# HTTP statuses only: no ids, no response bodies, no token.
#
# Run it with `bundle exec rake smoke`. See CONTRIBUTING.md.

require "date"
require "fileutils"
require "json"
require "securerandom"
require_relative "../lib/pennylane_client"
require_relative "live_reports"
require_relative "operation_table"

# Runs the smoke suite against a sandbox.
module Smoke
  TOKEN = "PENNYLANE_SMOKE_TOKEN"
  USER = "PENNYLANE_SMOKE_GITHUB_USER"
  SANDBOX = "PENNYLANE_SMOKE_SANDBOX"
  # Seconds before each request: at most 10 per 5 seconds.
  PACE = 0.5
  PASS = Checklist::LiveReports::PASS

  # Reads the environment, runs the suite and writes the report. Returns
  # the exit status: 1 when a result failed or the setup is incomplete.
  def self.main(env:, root:, out:, client: nil, operations: PennylaneClient::OPERATIONS,
                today: Date.today, sleeper: ->(seconds) { sleep(seconds) })
    token = env[TOKEN].to_s
    return skip(out) if token.empty?
    return refuse(out) unless Checklist::LiveReports::USER.match?(env[USER].to_s)

    plan = Plan.load(root, operations)
    runner = Runner.new(client: client || PennylaneClient.new(token: token), plan: plan, sleeper: sleeper, out: out)
    report = { root: root, date: today, user: env[USER], contract: plan.contract }
    summarise(out, Report.write(**report, operations: exercise(runner, env, out), checks: {}))
  end

  # The reads always; the writes only when the contributor says the token
  # belongs to a sandbox, since the client cannot tell.
  def self.exercise(runner, env, out)
    results = runner.reads
    return results.merge(runner.writes) if env[SANDBOX] == "yes"

    out.puts "Writes not run: set #{SANDBOX}=yes when the token belongs to a sandbox company."
    results
  end

  def self.skip(out)
    out.puts "Skipping rake smoke: set #{TOKEN} to a Pennylane sandbox token to run it. See CONTRIBUTING.md."
    0
  end

  def self.refuse(out)
    out.puts "Set #{USER} to your GitHub username: the report credits it in the checklist."
    1
  end

  def self.summarise(out, path)
    results = JSON.parse(File.read(path)).fetch("operations")
    counts = %w[pass fail not].to_h { |prefix| [prefix, results.count { |_, result| result.start_with?(prefix) }] }
    out.puts "#{counts["pass"]} passed, #{counts["fail"]} failed, #{counts["not"]} not run."
    out.puts "Wrote #{path}. Run `bundle exec rake checklist` and open a pull request with both."
    counts["fail"].zero? ? 0 : 1
  end
  private_class_method :exercise, :skip, :refuse, :summarise

  # What the smoke run reads: every live GET that needs no path param and no
  # required query param, then the detail read of the first item it lists.
  class Plan
    attr_reader :lists, :contract

    def self.load(root, operations)
      new(operations, JSON.parse(File.read(OperationTable.latest_snapshot(File.join(root, "docs/api/contract")))))
    end

    def initialize(operations, document)
      needs_query = Plan.needs_query(document)
      reads = operations.select { _1.verb == :get && !_1.deprecated }
      @lists = reads.reject { _1.path.include?("{") || needs_query.fetch(_1.id.to_s, true) }
      @details = reads.to_h { [_1.path, _1] }
      @contract = document.fetch("retrieved_on")
    end

    # The GET on "<list path>/{id}", or nil.
    def detail(list) = @details["#{list.path}/{id}"]

    # { operationId => true when it has a required query param }
    def self.needs_query(document)
      document.fetch("operations").to_h do |record|
        [record["operation_id"], record["parameters"].any? { _1["in"] == "query" && _1["required"] }]
      end
    end
  end

  # Sends the requests and records one result per operationId: "pass",
  # "fail: <status> <error class>", or "not run: 403 PermissionError" when
  # the token lacks the scope.
  class Runner
    # "fail: 500 ServerError", or "not run: 403 PermissionError" for a
    # missing scope. The message stays on the terminal: it can quote
    # sandbox data, and the report is committed.
    def self.outcome(error)
      prefix = error.is_a?(PennylaneClient::PermissionError) ? "not run" : "fail"
      "#{prefix}: #{[error.status, error.class.name.split("::").last].compact.join(" ")}"
    end

    # The smoke run's webhook subscription. Disabled, so Pennylane never
    # delivers to it; example.com, so nothing would receive it anyway.
    WEBHOOK = { callback_url: "https://example.com/pennylane-client-smoke", events: ["dms_file.created"],
                enabled: false }.freeze

    def initialize(client:, plan:, sleeper:, out: nil)
      @client = client
      @plan = plan
      @sleeper = sleeper
      @out = out
      @listed = {}
    end

    def reads
      @plan.lists.each_with_object({}) do |list, results|
        remember(list.id, attempt(results, list.id) { @client.call(list.id, **page_of_one(list)) })
        detail = @plan.detail(list)
        id = first_id(list.id)
        attempt(results, detail.id) { @client.call(detail.id, id: id) } if detail && id
      end
    end

    # Creates, reads, updates and deletes a contact on the first customer
    # and, when the company has none, a webhook subscription. Run `reads`
    # first. Everything created is deleted, even when a step fails.
    def writes
      results = {}
      contact(results)
      webhook(results)
      results
    end

    private

    def contact(results)
      customer_id = first_id(:getCustomers)
      return @out&.puts("No customer in the sandbox: contact writes not run.") unless customer_id

      attributes = { first_name: "pennylane_client", last_name: "smoke",
                     email: "smoke+#{SecureRandom.hex(4)}@example.com" }
      created = attempt(results, :postCustomerContact) do
        @client.call(:postCustomerContact, customer_id: customer_id, **attributes)
      end
      lifecycle(results, created, %i[getCustomerContact putCustomerContact deleteCustomerContact],
                { role: "smoke test" }, customer_id: customer_id)
    end

    def webhook(results)
      unless @listed[:getWebhookSubscriptions] == []
        return @out&.puts("The company has a webhook subscription, or listing failed: webhook writes not run.")
      end

      created = attempt(results, :postWebhookSubscriptions) { @client.call(:postWebhookSubscriptions, **WEBHOOK) }
      lifecycle(results, created, %i[getWebhookSubscription putWebhookSubscription deleteWebhookSubscription],
                WEBHOOK.slice(:events, :enabled))
    end

    # Reads, updates, then always deletes the record `created` holds.
    def lifecycle(results, created, (find, update, delete), changes, **scope)
      id = created[:id] if created.is_a?(Hash)
      return unless id

      attempt(results, find) { @client.call(find, **scope, id: id) }
      attempt(results, update) { @client.call(update, **scope, id: id, **changes) }
    ensure
      attempt(results, delete) { @client.call(delete, **scope, id: id) } if id
    end

    def attempt(results, operation_id)
      @sleeper.call(PACE)
      response = yield
      results[operation_id.to_s] = PASS
      response
    rescue PennylaneClient::Error => e
      @out&.puts "#{operation_id}: #{e.class.name}: #{e.message}"
      results[operation_id.to_s] = Runner.outcome(e)
      nil
    end

    def page_of_one(list) = list.paginated ? { limit: 1 } : {}

    def remember(list_id, response)
      items = response[:items] if response.is_a?(Hash)
      @listed[list_id] = items if items.is_a?(Array)
    end

    # The id of the first item a list read returned, or nil.
    def first_id(list_id)
      item = @listed.fetch(list_id, []).first
      item[:id] if item.is_a?(Hash)
    end
  end

  # Writes docs/api/live/<date>-<user>.json, the format LiveReports reads.
  module Report
    def self.write(root:, date:, user:, contract:, operations:, checks:)
      dir = File.join(root, Checklist::LiveReports::DIR)
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "#{date.iso8601}-#{user}.json")
      report = { "format" => Checklist::LiveReports::FORMAT, "verified_on" => date.iso8601, "by" => user,
                 "gem_version" => PennylaneClient::VERSION, "contract" => contract,
                 "operations" => operations.sort.to_h, "checks" => checks.sort.to_h }
      File.write(path, "#{JSON.pretty_generate(report)}\n")
      path
    end
  end
end

exit Smoke.main(env: ENV, root: File.expand_path("..", __dir__), out: $stdout) if $PROGRAM_NAME == __FILE__
