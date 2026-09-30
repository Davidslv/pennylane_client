# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tools/operation_table"
require "tmpdir"

module OperationTableFixtures
  # The fields of a snapshot record the table reads, with the rest left out.
  def record(id, method: "GET", path: "/api/external/v2/journals", **fields)
    {
      "operation_id" => id, "method" => method, "path" => path,
      "deprecated" => false, "parameters" => [], "request_body" => nil,
      "responses" => { "200" => {}, "404" => {} }
    }.merge(fields)
  end

  def json_body
    { "content" => { "application/json" => { "schema" => {} } }, "required" => true }
  end

  def multipart_body
    { "content" => { "multipart/form-data" => { "schema" => {} } }, "required" => true }
  end

  def cursor
    { "in" => "query", "name" => "cursor", "schema" => { "type" => "string" } }
  end

  def document(*records)
    { "retrieved_on" => "2026-09-30", "operations" => records }
  end
end

class OperationTableRowsTest < Minitest::Test
  include OperationTableFixtures

  def row_for(record)
    OperationTable.rows(document(record)).first
  end

  def test_builds_one_operation_per_record
    row = row_for(record("getJournal", path: "/api/external/v2/journals/{id}"))

    assert_equal PennylaneClient::Operation.new(
      id: :getJournal, verb: :get, path: "/api/external/v2/journals/{id}",
      paginated: false, body: nil, success: 200, deprecated: false
    ), row
  end

  def test_sorts_rows_by_operation_id_bytes_like_the_snapshot
    rows = OperationTable.rows(document(record("getJournals"), record("ValidateThing"), record("company-fiscal-years")))

    assert_equal %i[ValidateThing company-fiscal-years getJournals], rows.map(&:id)
  end

  def test_an_operation_is_paginated_when_it_takes_a_cursor_in_the_query
    assert row_for(record("getJournals", "parameters" => [cursor])).paginated
    refute row_for(record("getJournals", "parameters" => [cursor.merge("in" => "header")])).paginated
  end

  def test_returning_cursor_fields_without_taking_a_cursor_is_not_paginated
    limit = { "in" => "query", "name" => "limit" }

    refute row_for(record("getPaRegistrations", "parameters" => [limit])).paginated
  end

  def test_reads_the_body_kind_from_the_request_content_type
    assert_equal :json, row_for(record("postJournals", method: "POST", "request_body" => json_body)).body
    upload = record("postFileAttachments", method: "POST", "request_body" => multipart_body)

    assert_equal :multipart, row_for(upload).body
  end

  def test_refuses_a_content_type_it_does_not_know
    xml = { "content" => { "application/xml" => {} } }

    error = assert_raises(OperationTable::Error) { row_for(record("postXml", "request_body" => xml)) }
    assert_match(%r{postXml.*application/xml}, error.message)
  end

  def test_refuses_a_body_offered_in_more_than_one_content_type
    both = { "content" => json_body["content"].merge(multipart_body["content"]) }

    assert_raises(OperationTable::Error) { row_for(record("postBoth", "request_body" => both)) }
  end

  def test_takes_the_success_code_from_the_one_documented_2xx_response
    assert_equal 204, row_for(record("deleteJournal", "responses" => { "204" => {}, "404" => {} })).success
  end

  def test_refuses_an_operation_without_exactly_one_2xx_response
    none = record("getNothing", "responses" => { "404" => {} })
    two = record("getTwo", "responses" => { "200" => {}, "201" => {} })

    assert_raises(OperationTable::Error) { row_for(none) }
    assert_raises(OperationTable::Error) { row_for(two) }
  end

  def test_carries_the_deprecated_flag
    assert row_for(record("postLedgerAttachments", "deprecated" => true)).deprecated
  end
end

class OperationTableRenderTest < Minitest::Test
  include OperationTableFixtures

  def rows
    OperationTable.rows(document(
                          record("getJournal", path: "/api/external/v2/journals/{id}"),
                          record("company-fiscal-years", path: "/api/external/v2/fiscal_years",
                                                         "parameters" => [cursor]),
                          record("postFileAttachments", method: "POST", path: "/api/external/v2/file_attachments",
                                                        "request_body" => multipart_body,
                                                        "responses" => { "201" => {} })
                        ))
  end

  def test_each_row_literal_evaluates_back_to_the_same_operation
    rows.each do |row|
      assert_equal row, PennylaneClient.module_eval(OperationTable.literal(row))
    end
  end

  def test_renders_one_line_per_operation_so_drift_shows_as_one_line_diffs
    source = OperationTable.render(rows, source: "docs/api/contract/2026-09-30/operations.json")
    lines = source.lines.grep(/Operation\.new/)

    assert_equal 3, lines.size
    assert_includes lines.first, 'id: :"company-fiscal-years"'
  end

  def test_names_its_source_and_says_it_is_generated
    source = OperationTable.render(rows, source: "docs/api/contract/2026-09-30/operations.json")

    assert_includes source, "# frozen_string_literal: true"
    assert_includes source, "docs/api/contract/2026-09-30/operations.json"
    assert_match(/Do not edit by hand/, source)
  end

  def test_renders_a_frozen_table_that_loads
    # Load it inside a throwaway namespace so the real table is untouched.
    sandbox = Module.new
    sandbox.const_set(:Operation, PennylaneClient::Operation)
    sandbox.module_eval(OperationTable.render(rows, source: "x"))
    loaded = sandbox::PennylaneClient::OPERATIONS

    assert_equal rows, loaded
    assert_predicate loaded, :frozen?
  end

  def test_row_order_in_does_not_change_the_output
    assert_equal OperationTable.render(rows, source: "x"), OperationTable.render(rows.reverse, source: "x")
  end
end

class OperationTableSnapshotTest < Minitest::Test
  def test_picks_the_latest_dated_snapshot
    Dir.mktmpdir do |root|
      %w[2026-09-29 2026-09-30 2026-10-01-notes].each { FileUtils.mkdir_p(File.join(root, _1)) }
      %w[2026-09-29 2026-09-30].each { File.write(File.join(root, _1, "operations.json"), "{}") }

      assert_equal File.join(root, "2026-09-30", "operations.json"), OperationTable.latest_snapshot(root)
    end
  end

  def test_refuses_a_root_with_no_snapshot
    Dir.mktmpdir do |root|
      assert_raises(OperationTable::Error) { OperationTable.latest_snapshot(root) }
    end
  end
end
