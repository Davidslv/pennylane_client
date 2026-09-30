# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tools/contract_drift"
require_relative "snapshot_contract_test" # for SnapshotContractFixtures
require "tmpdir"

module ContractDriftFixtures
  JOURNAL = {
    "operation_id" => "getJournal", "method" => "GET", "path" => "/api/external/v2/journals/{id}",
    "summary" => "Retrieve a journal", "description" => "Retrieve a journal", "tags" => ["Journals"],
    "scopes" => [%w[journals:all journals:readonly]], "deprecated" => false,
    "parameters" => [
      { "description" => "The journal", "example" => 42, "in" => "path", "name" => "id", "required" => true,
        "schema" => { "type" => "integer" } }
    ],
    "request_body" => nil,
    "responses" => {
      "200" => {
        "content" => {
          "application/json" => {
            "schema" => {
              "properties" => {
                "description" => { "type" => "string" },
                "id" => { "description" => "The id", "type" => "integer" }
              },
              "required" => %w[id description],
              "type" => "object"
            }
          }
        },
        "description" => "OK"
      }
    },
    "source_url" => "https://pennylane.readme.io/reference/getjournal.md"
  }.freeze

  ATTACHMENTS = {
    "operation_id" => "postLedgerAttachments", "method" => "POST", "path" => "/api/external/v2/ledger_attachments",
    "tags" => ["Ledger attachments"], "scopes" => [], "deprecated" => false, "parameters" => [],
    "request_body" => nil, "responses" => { "201" => {} }
  }.freeze

  SCHEMA = "responses.200.content.application/json.schema"

  # A deep copy of record, changed by the block.
  def edited(record)
    copy = JSON.parse(JSON.generate(record))
    yield copy
    copy
  end

  def schema(record)
    record.dig("responses", "200", "content", "application/json", "schema")
  end

  def diff(old, new)
    ContractDrift::Diff.new(old, new)
  end

  # A stand-in for the gh CLI that records [args, stdin] and answers
  # `gh issue list` with the open drift issue's number, if any.
  def fake_gh(open_issue: nil)
    calls = []
    runner = lambda do |*args, stdin: nil|
      calls << [args, stdin]
      args.first(2) == %w[issue list] ? "#{open_issue}\n" : ""
    end
    [runner, calls]
  end
end

# What is and is not drift.
class ContractDriftNoiseTest < Minitest::Test
  include ContractDriftFixtures

  def test_the_same_operations_make_no_drift
    assert_empty diff([JOURNAL, ATTACHMENTS], [JOURNAL, ATTACHMENTS])
  end

  def test_operation_text_is_not_drift
    reworded = edited(JOURNAL) do |record|
      record["summary"] = "Get a journal"
      record["description"] = "Fetch one journal"
      record["source_url"] = "https://pennylane.readme.io/reference/getjournal-1.md"
    end

    assert_empty diff([JOURNAL], [reworded])
  end

  def test_parameter_and_schema_text_is_not_drift
    reworded = edited(JOURNAL) do |record|
      record["parameters"][0].merge!("description" => "Its id", "example" => 7)
      record["responses"]["200"]["description"] = "Success"
      schema(record)["properties"]["id"]["description"] = "Id"
    end

    assert_empty diff([JOURNAL], [reworded])
  end

  def test_a_field_named_description_is_still_compared
    retyped = edited(JOURNAL) { schema(_1)["properties"]["description"]["type"] = "integer" }

    assert_equal [["getJournal", :changed, "#{SCHEMA}.properties.description.type", "string", "integer"]],
                 diff([JOURNAL], [retyped]).changes
  end

  def test_the_order_of_a_required_list_is_not_drift
    reordered = edited(JOURNAL) { schema(_1)["required"] = %w[description id] }

    assert_empty diff([JOURNAL], [reordered])
  end

  def test_a_schema_title_is_text_but_a_field_named_title_is_not
    with_variant = edited(JOURNAL) { schema(_1)["title"] = "Journal" }
    renamed = edited(with_variant) { schema(_1)["title"] = "Ledger journal" }

    assert_empty diff([with_variant], [renamed])
    titled = edited(JOURNAL) { schema(_1)["properties"]["title"] = { "type" => "string" } }

    assert_equal [["getJournal", :added, "#{SCHEMA}.properties.title", nil, nil]], diff([JOURNAL], [titled]).changes
  end

  # JOURNAL whose response schema is oneOf the given kinds of document.
  def one_of(*kinds)
    variants = kinds.map { { "title" => _1, "properties" => { "kind" => { "enum" => [_1] } } } }
    edited(JOURNAL) { schema(_1)["oneOf"] = variants }
  end

  def test_a_variant_inserted_first_in_one_of_is_one_addition
    changes = diff([one_of("invoice", "credit_note")], [one_of("quote", "invoice", "credit_note")]).changes

    assert_equal([:added], changes.map { _1[1] })
    assert_match(/\A#{Regexp.escape(SCHEMA)}\.oneOf\.\h{8}\z/o, changes[0][2])
  end
end

# How drift is described.
class ContractDriftDiffTest < Minitest::Test
  include ContractDriftFixtures

  def test_lists_added_and_removed_operations
    drift = diff([JOURNAL], [ATTACHMENTS])

    assert_equal [ATTACHMENTS], drift.added
    assert_equal [JOURNAL], drift.removed
  end

  def test_lists_newly_deprecated_operations
    deprecated = edited(ATTACHMENTS) { _1["deprecated"] = true }

    assert_equal [deprecated], diff([ATTACHMENTS], [deprecated]).deprecated
    assert_empty diff([deprecated], [deprecated]).deprecated
  end

  def test_a_new_parameter_is_one_addition_named_by_location_and_name
    filtered = edited(JOURNAL) do |record|
      record["parameters"] << { "in" => "query", "name" => "filter", "schema" => { "type" => "string" } }
    end

    assert_equal [["getJournal", :added, "parameters.query:filter", nil, nil]], diff([JOURNAL], [filtered]).changes
  end

  def test_a_new_response_field_is_one_addition_not_one_per_leaf
    widened = edited(JOURNAL) { schema(_1)["properties"]["label"] = { "type" => "string", "nullable" => true } }

    assert_equal [["getJournal", :added, "#{SCHEMA}.properties.label", nil, nil]], diff([JOURNAL], [widened]).changes
  end

  def test_a_removed_response_code_is_one_removal
    narrowed = edited(JOURNAL) { _1["responses"]["404"] = { "description" => "Missing" } }

    assert_equal [["getJournal", :removed, "responses.404", nil, nil]], diff([narrowed], [JOURNAL]).changes
  end

  def test_a_changed_method_path_or_scope_is_a_change
    moved = edited(JOURNAL) do |record|
      record.merge!("method" => "POST", "path" => "/api/external/v2/journal/{id}", "scopes" => [["journals:all"]])
    end

    assert_equal [
      ["getJournal", :changed, "method", "GET", "POST"],
      ["getJournal", :changed, "path", "/api/external/v2/journals/{id}", "/api/external/v2/journal/{id}"],
      ["getJournal", :changed, "scopes", [%w[journals:all journals:readonly]], [["journals:all"]]]
    ], diff([JOURNAL], [moved]).changes
  end
end

# Two snapshot folders compared and written up as an issue body.
class ContractDriftReportTest < Minitest::Test
  include ContractDriftFixtures

  ERRORS = { "errors.md" => "# Errors\n" }.freeze
  HEADER = "<!--\n  Source: https://example.test/guide.md\n  Retrieved: %s\n-->\n\n"

  def write_snapshot(root, date, operations, guides)
    dir = File.join(root, date)
    FileUtils.mkdir_p(File.join(dir, "guides"))
    File.write(File.join(dir, "operations.json"), JSON.generate("retrieved_on" => date, "operations" => operations))
    guides.each { |name, body| File.write(File.join(dir, "guides", name), format(HEADER, date) + body) }
    dir
  end

  def compare(old_operations, new_operations, new_guides: ERRORS)
    Dir.mktmpdir do |root|
      committed = write_snapshot(root, "2026-09-30", old_operations, ERRORS)
      fresh = write_snapshot(File.join(root, "fresh"), "2026-10-07", new_operations, new_guides)
      ContractDrift.compare(committed: committed, fresh: fresh, committed_label: "docs/api/contract/2026-09-30")
    end
  end

  def test_the_same_snapshot_on_a_later_day_is_no_drift
    report = compare([JOURNAL], [JOURNAL])

    assert_empty report
    assert_nil report.to_markdown
  end

  def test_a_changed_guide_body_is_drift_but_its_retrieval_header_is_not
    report = compare([JOURNAL], [JOURNAL], new_guides: { "errors.md" => "# Errors\n\nNow with 422.\n" })

    refute_empty report
    assert_includes report.to_markdown, "### Changed guides\n\n- `errors.md`\n"
  end

  EVERY_KIND = <<~MARKDOWN
    Pennylane's published docs no longer match the committed contract snapshot.

    - Committed snapshot: `docs/api/contract/2026-09-30`
    - Docs retrieved: 2026-10-07

    Apply the drift in a pull request: `bundle exec rake contract:snapshot contract:sync checklist`, then the code that matches.

    ### New operations

    - `deleteJournal` DELETE /api/external/v2/journals/{id}

    ### Newly deprecated operations

    - `postLedgerAttachments` POST /api/external/v2/ledger_attachments

    ### Changed operations

    #### `getJournal` GET /api/external/v2/journals/{id}

    - changed `parameters.path:id.schema.type`: `"integer"` → `"string"`
  MARKDOWN

  def test_the_report_lists_every_kind_of_change
    retyped = edited(JOURNAL) { _1["parameters"][0]["schema"]["type"] = "string" }
    added = JOURNAL.merge("operation_id" => "deleteJournal", "method" => "DELETE")

    report = compare([JOURNAL, ATTACHMENTS], [retyped, ATTACHMENTS.merge("deprecated" => true), added])

    assert_equal EVERY_KIND, report.to_markdown
  end

  def test_removed_operations_and_added_and_removed_fields_are_listed
    widened = edited(JOURNAL) do |record|
      record["parameters"] << { "in" => "query", "name" => "filter" }
      record["responses"].delete("200")
    end

    markdown = compare([JOURNAL, ATTACHMENTS], [widened]).to_markdown

    assert_includes markdown, "### Removed operations\n\n- `postLedgerAttachments` POST #{ATTACHMENTS["path"]}\n"
    assert_includes markdown, "- added `parameters.query:filter`\n"
    assert_includes markdown, "- removed `responses.200`\n"
  end

  def test_a_report_too_long_for_an_issue_is_cut_with_a_note
    report = compare([], (1..3000).map { |n| JOURNAL.merge("operation_id" => "getJournal#{n}") })

    assert_operator report.to_markdown.length, :<=, ContractDrift::Report::LIMIT
    assert report.to_markdown.end_with?("Run `bundle exec rake contract:drift` locally for the full report.\n")
    assert_includes report.to_markdown(limit: nil), "getJournal3000"
  end
end

# Opening or updating the one drift issue. `gh` is recorded, never run.
class ContractDriftIssueTest < Minitest::Test
  include ContractDriftFixtures

  def report(old, new)
    ContractDrift::Report.new(diff: diff(old, new), guides: [], committed: "c", retrieved_on: "2026-10-07")
  end

  def test_no_drift_touches_no_issue
    runner, calls = fake_gh

    assert_equal "No drift.", ContractDrift::Issue.sync(report([JOURNAL], [JOURNAL]), cli: runner)
    assert_empty calls
  end

  def test_drift_opens_a_labelled_issue_when_none_is_open
    runner, calls = fake_gh
    drift = report([JOURNAL], [JOURNAL, ATTACHMENTS])

    assert_equal "Opened a drift issue.", ContractDrift::Issue.sync(drift, cli: runner)
    assert_equal [%w[issue list --label drift --state open --json number --jq .[0].number], nil], calls[0]
    assert_equal %w[label create drift], calls[1][0].first(3)
    assert_equal [["issue", "create", "--title", ContractDrift::Issue::TITLE, "--label", "drift",
                   "--body-file", "-"], drift.to_markdown], calls[2]
  end

  def test_drift_updates_the_open_issue_instead_of_opening_another
    runner, calls = fake_gh(open_issue: 31)
    drift = report([JOURNAL], [JOURNAL, ATTACHMENTS])

    assert_equal "Updated drift issue #31.", ContractDrift::Issue.sync(drift, cli: runner)
    assert_equal [[%w[issue edit 31 --body-file -], drift.to_markdown]], calls.drop(1)
  end
end

# The whole run: snapshot the (fixture) docs into a temporary folder and
# compare with the latest committed snapshot.
class ContractDriftRunTest < Minitest::Test
  include SnapshotContractFixtures
  include ContractDriftFixtures

  def served(pages = site)
    pages.merge(SnapshotContract::GUIDES.to_h { |_name, url| [url, "# Guide\n\nBody of #{url}\n"] })
  end

  def with_committed_snapshot
    Dir.mktmpdir do |root|
      contract = File.join(root, "docs/api/contract")
      SnapshotContract.run(fetch: served.method(:[]), root: contract, date: Date.new(2026, 9, 30), warn: ->(_) {})
      yield root
    end
  end

  def drift(root, pages)
    ContractDrift.run(fetch: pages.method(:[]), root: root, date: Date.new(2026, 10, 7), warn: ->(_) {})
  end

  def test_unchanged_docs_are_no_drift
    with_committed_snapshot { |root| assert_empty drift(root, served) }
  end

  def test_a_changed_page_is_drift_against_the_committed_snapshot
    url = "https://pennylane.readme.io/reference/getjournal.md"
    changed = page("getjournal").sub(/("label": \{\s+"type": )"string"/, '\1"integer"')

    with_committed_snapshot do |root|
      markdown = drift(root, served(site.merge(url => changed))).to_markdown

      assert_includes markdown, "- Committed snapshot: `docs/api/contract/2026-09-30`\n"
      assert_includes markdown, "- changed `responses.200.content.application/json.schema.properties.label.type`: " \
                                "`\"string\"` → `\"integer\"`\n"
      assert_equal ["2026-09-30"], Dir.children(File.join(root, "docs/api/contract")), "drift never writes a snapshot"
    end
  end

  def test_a_changed_page_opens_an_issue_listing_the_change
    url = "https://pennylane.readme.io/reference/getjournal.md"
    changed = page("getjournal").sub(/("label": \{\s+"type": )"string"/, '\1"integer"')
    runner, calls = fake_gh

    with_committed_snapshot do |root|
      assert_equal "Opened a drift issue.", ContractDrift::Issue.sync(drift(root, served(site.merge(url => changed))),
                                                                      cli: runner)
    end
    args, body = calls.last

    assert_equal %w[issue create], args.first(2)
    assert_includes body, "properties.label.type`: `\"string\"` → `\"integer\"`"
  end

  # A contract the snapshot tool refuses is drift too: say so in the issue
  # rather than only failing the scheduled run.
  def test_docs_the_snapshot_tool_refuses_are_reported_as_drift
    duplicated = site.merge("https://pennylane.readme.io/reference/postjournals.md" => page("getjournal"))

    with_committed_snapshot do |root|
      report = drift(root, served(duplicated))

      refute_empty report
      assert_includes report.to_markdown, "### The snapshot tool refused the docs\n\n"
      assert_includes report.to_markdown, "getJournal is documented more than once"
    end
  end

  def test_a_docs_site_outage_fails_the_run_instead_of_reporting_drift
    outage = ->(url) { raise SnapshotContract::FetchError, "GET #{url}: HTTP 503" }

    with_committed_snapshot do |root|
      assert_raises(SnapshotContract::FetchError) do
        ContractDrift.run(fetch: outage, root: root, date: Date.new(2026, 10, 7), warn: ->(_) {})
      end
    end
  end
end
