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
  PROBE = "PENNYLANE_SMOKE_PROBE_429"
  # Seconds before each request: at most 10 per 5 seconds.
  PACE = 0.5
  PASS = Checklist::LiveReports::PASS

  # Reads the environment, runs the suite and writes the report. Returns
  # the exit status: 1 when a result failed or the setup is incomplete.
  # Other keywords go to `run`; tests pass `client`, `probe_client`,
  # `operations`, `today` and `sleeper`.
  def self.main(env:, root:, out:, **)
    token = env[TOKEN].to_s
    return skip(out) if token.empty?
    return refuse(out) unless Checklist::LiveReports::USER.match?(env[USER].to_s)

    summarise(out, run(env: env, root: root, out: out, token: token, **))
  end

  # Runs the suite and writes the report. Returns the report's path.
  def self.run(env:, root:, out:, token:, client: nil, probe_client: nil, operations: PennylaneClient::OPERATIONS,
               today: Date.today, sleeper: ->(seconds) { sleep(seconds) })
    client ||= PennylaneClient.new(token: token)
    plan = Plan.load(root, operations)
    runner = Runner.new(client: client, plan: plan, sleeper: sleeper, out: out)
    results = exercise(runner, env, out)
    checks = checks(env) do
      RateLimitProbe.new(client: probe_client || probe_client(token), reader: client,
                         customer_id: runner.customer_id, sleeper: sleeper, out: out)
    end
    Report.write(root: root, date: today, user: env[USER], contract: plan.contract,
                 operations: results, checks: checks)
  end

  # A client with no client-side limit that never retries, so a 429 comes
  # straight back and each write goes out once (RateLimitProbe). A negative
  # wait budget refuses even a `retry-after: 0`. Never used for anything else.
  def self.probe_client(token)
    PennylaneClient.new(token: token, limiters: PennylaneClient::LimiterRegistry.new { Unlimited.new },
                        max_retry_wait: -1.0)
  end

  # The yielded RateLimitProbe runs only when the contributor asked for it
  # on a sandbox.
  def self.checks(env)
    probe_asked = env[SANDBOX] == "yes" && env[PROBE] == "yes"
    { "webhook_signature" => Checks.webhook_signature(env),
      "rate_limited_write_not_executed" =>
        probe_asked ? yield.run : "#{Checks::NOT_RUN}: set #{SANDBOX}=yes and #{PROBE}=yes to probe" }
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

  # Prints the tally and returns 1 when any operation or check failed.
  def self.summarise(out, path)
    report = JSON.parse(File.read(path))
    results = report.fetch("operations").values
    out.puts tally(results)
    report.fetch("checks").each { |check, result| out.puts "#{check}: #{result}" }
    out.puts "Wrote #{path}. Run `bundle exec rake checklist` and open a pull request with both."
    [*results, *report.fetch("checks").values].any? { _1.start_with?("fail") } ? 1 : 0
  end

  # What a contributor deletes by hand when cleanup failed. Printed to the
  # terminal only; the report never holds ids.
  def self.leftover(operation_id, **params)
    "Delete by hand: #{operation_id} #{params.map { |key, value| "#{key}=#{value}" }.join(" ")}"
  end

  def self.tally(results)
    count = ->(prefix) { results.count { _1.start_with?(prefix) } }
    "#{count.call("pass")} passed, #{count.call("fail")} failed, #{count.call("not run")} not run."
  end
  private_class_method :run, :checks, :exercise, :skip, :refuse, :summarise, :tally

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

    # The first customer `reads` listed, or nil.
    def customer_id = first_id(:getCustomers)

    private

    def contact(results)
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
      if id
        attempt(results, delete) { @client.call(delete, **scope, id: id) }
        @out&.puts Smoke.leftover(delete, **scope, id: id) unless results[delete.to_s] == PASS
      end
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

  # The open questions in proposal 0001 that only a sandbox can settle.
  module Checks
    NOT_RUN = Checklist::LiveReports::NOT_RUN
    WEBHOOK = %w[PENNYLANE_SMOKE_WEBHOOK_BODY PENNYLANE_SMOKE_WEBHOOK_SIGNATURE PENNYLANE_SMOKE_WEBHOOK_SECRET].freeze

    # webhook_signature: a delivery the contributor captured from their
    # sandbox verifies. The age is not checked: the capture is older than
    # the tolerance by the time the smoke run reads it.
    def self.webhook_signature(env)
      body_file, signature, secret = env.values_at(*WEBHOOK)
      return NOT_RUN if [body_file, signature, secret].any? { _1.to_s.empty? }

      PennylaneClient::Webhook.verify!(File.binread(body_file), signature, secret: secret, tolerance: nil)
      PASS
    rescue SystemCallError
      "#{NOT_RUN}: cannot read #{WEBHOOK.first}"
    rescue PennylaneClient::SignatureError => e
      "fail: #{e.message}"
    end
  end

  # rate_limited_write_not_executed: D5 retries a POST after a 429 on the
  # assumption that Pennylane did not run it. This sends up to BURST GETs
  # with no client-side limit until Pennylane answers 429, sends one
  # contact create into the exhausted window, waits out `retry-after`, and
  # looks for the contact. It is the only point where the smoke run reaches
  # the rate limit, once, on purpose, and only when asked.
  class RateLimitProbe
    BURST = 30

    # `client` must have no client-side limit and no retry wait
    # (Smoke.probe_client); `reader` is the paced client.
    def initialize(client:, reader:, customer_id:, sleeper:, out: nil)
      @client = client
      @reader = reader
      @customer_id = customer_id
      @sleeper = sleeper
      @out = out
    end

    def run
      return "#{Checks::NOT_RUN}: no customer in the sandbox" unless @customer_id
      return "#{Checks::NOT_RUN}: no 429 within #{BURST} requests" unless exhaust

      email = "smoke-429+#{SecureRandom.hex(4)}@example.com"
      verdict(email, write(email))
    rescue PennylaneClient::Error => e
      "#{Checks::NOT_RUN}: #{Runner.outcome(e).split(": ", 2).last}"
    end

    private

    def exhaust
      BURST.times { @client.call(:getMe) }
      false
    rescue PennylaneClient::RateLimitError
      true
    end

    # The seconds to wait when the write was rate-limited, else nil.
    def write(email)
      created = @client.call(:postCustomerContact, customer_id: @customer_id, first_name: "pennylane_client",
                                                   last_name: "smoke 429", email: email)
      delete(created[:id])
      nil
    rescue PennylaneClient::RateLimitError => e
      e.retry_after || 5.0
    end

    def verdict(email, wait)
      return "#{Checks::NOT_RUN}: the write was not rate-limited" unless wait

      @sleeper.call(wait + 1)
      leaked = @reader.paginate(:getCustomerContacts, customer_id: @customer_id).find { _1[:email] == email }
      return PASS unless leaked

      delete(leaked[:id])
      "fail: the rate-limited write was executed"
    end

    def delete(id)
      @reader.call(:deleteCustomerContact, customer_id: @customer_id, id: id)
    rescue PennylaneClient::Error
      @out&.puts Smoke.leftover(:deleteCustomerContact, customer_id: @customer_id, id: id)
      raise
    end
  end

  # A limiter that never waits, for the probe client only.
  class Unlimited
    def acquire = 0.0
    def update(**) = nil
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
