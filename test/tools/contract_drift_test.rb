# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tools/contract_drift"
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

    #### `postLedgerAttachments` POST /api/external/v2/ledger_attachments

    - changed `deprecated`: `false` → `true`
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
