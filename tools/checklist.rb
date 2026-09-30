# frozen_string_literal: true

# Generate docs/api/CHECKLIST.md from the latest contract snapshot, the
# generated operation table and the behaviour tests.
#
# Why: "complete" has to be something CI checks, not something we claim.
# Every column is derived: registered from the operation table, named from
# behaviour tests that name the operationId, live from sandbox evidence
# (none yet). Nothing is ticked by hand, so the checklist cannot lie.
#
# Standard library only. Run it with `bundle exec rake checklist`.

require "json"
require_relative "operation_table"

# Renders the operation checklist.
module Checklist
  class Error < StandardError; end

  PREFIX = "/api/external/v2"
  UNVERIFIED = "unverified: no sandbox access"
  DEPRECATED = "skipped: deprecated"

  # Finds the behaviour tests that name an Operation. A test names one with
  # a comment directly above its method, one operationId per line:
  #
  #   # names: finalizeCustomerInvoice
  #   def test_finalize
  #
  # Only test/resources/ is read, so the contract test can never count.
  module NamedTests
    GLOB = "test/resources/**/*_test.rb"
    MARKER = /\A\s*#\s*names:\s*([\w-]+)\s*\z/
    # Anything that looks like a marker but is not one fails, so a typo
    # never leaves an operation silently unnamed.
    MARKER_LIKE = /\A\s*#\s*names\s*:/i
    COMMENT = /\A\s*#/
    TEST = /\A\s*def\s+(test_\w+)/

    # Returns { operationId => ["test/resources/x_test.rb#test_name", ...] }.
    def self.scan(root:, known:)
      named = Hash.new { |hash, id| hash[id] = [] }
      Dir.glob(GLOB, base: root).sort.each do |file|
        each_marker(File.read(File.join(root, file)), file) do |id, test|
          raise Error, "#{file}: #{id} is not an operationId in the snapshot" unless known.include?(id)

          named[id] |= ["#{file}##{test}"]
        end
      end
      named.to_h
    end

    # Yields [operationId, test name] for each marker. Markers wait in
    # `pending` until the next test method; any other code first is an error.
    def self.each_marker(source, file, &block)
      pending = []
      source.each_line.with_index(1) { |line, number| read_line(line, number, pending, file, &block) }
      refuse_stray(pending, file)
    end

    def self.read_line(line, number, pending, file)
      if (marker = MARKER.match(line)) then pending << [marker[1], number]
      elsif MARKER_LIKE.match?(line) then raise Error, "#{file}:#{number}: use \"# names: <operationId>\""
      elsif (test = TEST.match(line)) then pending.shift(pending.size).each { |marked| yield marked.first, test[1] }
      elsif !COMMENT.match?(line) then refuse_stray(pending, file)
      end
    end

    def self.refuse_stray(pending, file)
      return if pending.empty?

      id, number = pending.first
      raise Error, "#{file}:#{number}: \"# names: #{id}\" must sit directly above a test method"
    end
    private_class_method :each_marker, :read_line, :refuse_stray
  end

  # Reads the sandbox reports `rake smoke` writes to docs/api/live/. A report
  # is JSON:
  #
  #   {"format": 1, "verified_on": "2026-10-01", "by": "octocat",
  #    "operations": {"getMe": "pass", "getJournals": "fail: 403 ..."},
  #    "checks": {"webhook_signature": "pass"}}
  #
  # Reports are read oldest first, so for each operation the latest report
  # that ran it decides: "pass" verifies it, anything else leaves it
  # unverified. A check keeps its latest result other than "not run".
  module LiveReports
    GLOB = "docs/api/live/*.json"
    FORMAT = 1
    DATE = /\A\d{4}-\d{2}-\d{2}\z/
    # A GitHub username.
    USER = /\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\z/
    PASS = "pass"
    NOT_RUN = "not run"

    # verified: { operationId => [date, user] }
    # checks:   { check => [result, date, user] }
    Live = Data.define(:verified, :checks)
    NONE = Live.new(verified: {}.freeze, checks: {}.freeze)

    def self.scan(root:, known:)
      reports = Dir.glob(GLOB, base: root).map { |file| read(File.join(root, file), file, known) }
      reports.sort_by { [_1.fetch("verified_on"), _1.fetch("file")] }
             .each_with_object(Live.new(verified: {}, checks: {})) { |report, live| apply(report, live) }
    end

    def self.read(path, file, known)
      report = JSON.parse(File.read(path))
      validate(report, file)
      unknown = report.fetch("operations").keys - known
      raise Error, "#{file}: #{unknown.join(", ")} not an operationId in the snapshot" if unknown.any?

      report.merge("file" => file)
    rescue JSON::ParserError, KeyError, NoMethodError => e
      raise Error, "#{file}: not a sandbox report (#{e.message})"
    end

    def self.validate(report, file)
      raise Error, "#{file}: format must be #{FORMAT}" unless report["format"] == FORMAT
      raise Error, "#{file}: verified_on must be YYYY-MM-DD" unless DATE.match?(report["verified_on"].to_s)
      raise Error, "#{file}: by must be a GitHub username" unless USER.match?(report["by"].to_s)
    end

    def self.apply(report, live)
      stamp = report.values_at("verified_on", "by")
      report.fetch("operations").each do |id, result|
        result == PASS ? live.verified[id] = stamp : live.verified.delete(id)
      end
      report.fetch("checks", {}).each do |check, result|
        live.checks[check] = [result, *stamp] unless result == NOT_RUN
      end
    end
    private_class_method :read, :validate, :apply
  end

  def self.render(document, source:, registered:, named:, live: LiveReports::NONE)
    operations = document.fetch("operations")
    registered = registered.to_set
    [
      header(source, document.fetch("retrieved_on")),
      summary(operations, registered, named, live),
      *checks(live),
      *groups(operations).map { |group, rows| section(group, rows, registered, named, live) }
    ].join("\n")
  end

  def self.header(source, date)
    <<~MARKDOWN
      <!--
        Generated by `rake checklist` from #{source},
        lib/pennylane_client/operations.rb, the behaviour tests under test/resources/
        and the sandbox reports under docs/api/live/.
        Do not edit by hand: `rake stale` fails when this file differs from what the generator writes.
      -->

      # Operation checklist

      Contract snapshot of #{date}. One row per Operation, grouped by resource group (Pennylane's tag). Paths are relative to `#{PREFIX}`.

      - **registered**: in the generated operation table, so `client.call` can reach it.
      - **named**: a behaviour test in `test/resources/` names the operationId with `# names: <operationId>` directly above it. The contract test never counts.
      - **live**: `sandbox-verified <date> (by @user)` when the latest sandbox report in `docs/api/live/` that ran it passed (`rake smoke`), `#{UNVERIFIED}`, or `#{DEPRECATED}`.
    MARKDOWN
  end

  def self.summary(operations, registered, named, verified)
    live = operations.reject { _1["deprecated"] }
    <<~MARKDOWN
      | | Operations |
      |---|---|
      | In the snapshot | #{operations.size} |
      | Live (not deprecated) | #{live.size} |
      | Registered | #{operations.count { registered.include?(_1["operation_id"]) }} |
      | Named | #{live.count { named.key?(_1["operation_id"]) }} of #{live.size} live |
      | Live-verified | #{verified_count(operations, verified)} of #{live.size} live |
    MARKDOWN
  end

  # How many live operations a sandbox report verified.
  def self.verified_count(operations, live)
    operations.count { !_1["deprecated"] && live.verified.key?(_1["operation_id"]) }
  end

  # The open questions `rake smoke` checks, with their latest result.
  def self.checks(live)
    return [] if live.checks.empty?

    rows = live.checks.sort.map { |check, (result, date, user)| "| `#{check}` | #{result} | #{date} (by @#{user}) |" }
    [<<~MARKDOWN]
      ## Sandbox checks

      | Check | Result | Run |
      |---|---|---|
      #{rows.join("\n")}
    MARKDOWN
  end

  def self.groups(operations)
    operations.group_by { _1.fetch("tags").first || "Untagged" }
              .sort_by { |group, _| [group.downcase, group] }
              .map { |group, rows| [group, rows.sort_by { _1.values_at("path", "method") }] }
  end

  def self.section(group, rows, registered, named, verified)
    live = rows.reject { _1["deprecated"] }
    lines = rows.map { |operation| row(operation, registered, named, verified) }
    <<~MARKDOWN
      ## #{group} (#{live.count { named.key?(_1["operation_id"]) }} of #{live.size} named)

      | operationId | Method | Path | registered | named | live | proven by |
      |---|---|---|---|---|---|---|
      #{lines.join("\n")}
    MARKDOWN
  end

  def self.row(operation, registered, named, live)
    id = operation.fetch("operation_id")
    tests = named.fetch(id, [])
    cells = [
      "`#{id}`", operation.fetch("method"), "`#{operation.fetch("path").delete_prefix(PREFIX)}`",
      registered.include?(id) ? "yes" : "no", tests.empty? ? "no" : "yes",
      live_cell(operation, live), tests.map { "`#{_1}`" }.join("<br>")
    ]
    "| #{cells.join(" | ")} |"
  end

  def self.live_cell(operation, live)
    return DEPRECATED if operation["deprecated"]

    date, user = live.verified[operation.fetch("operation_id")]
    date ? "sandbox-verified #{date} (by @#{user})" : UNVERIFIED
  end
  private_class_method :header, :summary, :verified_count, :checks, :groups, :section, :row, :live_cell

  # Reads the latest snapshot, the behaviour tests and the sandbox reports
  # under root and returns the checklist.
  def self.generate(root:, registered:)
    snapshot = OperationTable.latest_snapshot(File.join(root, "docs/api/contract"))
    document = JSON.parse(File.read(snapshot))
    known = document.fetch("operations").map { _1["operation_id"] }
    render(document, source: snapshot.delete_prefix("#{root}/"),
                     registered: registered, named: NamedTests.scan(root: root, known: known),
                     live: LiveReports.scan(root: root, known: known))
  end
end

if $PROGRAM_NAME == __FILE__
  require_relative "../lib/pennylane_client"

  root = File.expand_path("..", __dir__)
  target = File.join(root, "docs/api/CHECKLIST.md")
  File.write(target, Checklist.generate(root: root, registered: PennylaneClient::OPERATIONS.map { _1.id.to_s }))
  puts "Wrote #{target}"
end
