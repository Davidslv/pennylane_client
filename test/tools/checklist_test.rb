# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tools/checklist"
require "tmpdir"

module ChecklistFixtures
  def record(id, tag, method: "GET", path: "/api/external/v2/journals", deprecated: false)
    { "operation_id" => id, "method" => method, "path" => path, "tags" => [tag], "deprecated" => deprecated }
  end

  def document
    deprecated = record("postLedgerAttachments", "Ledger Attachments",
                        method: "POST", path: "/api/external/v2/ledger_attachments", deprecated: true)
    journals = [record("getJournal", "Journals", path: "/api/external/v2/journals/{id}"),
                record("getJournals", "Journals"), record("postJournals", "Journals", method: "POST")]
    { "retrieved_on" => "2026-09-30", "operations" => journals + [deprecated] }
  end

  def registered
    %w[getJournal getJournals postJournals postLedgerAttachments]
  end

  def render(named: {}, registered: self.registered)
    Checklist.render(document, source: "docs/api/contract/2026-09-30/operations.json",
                               registered: registered, named: named)
  end

  def row(markdown, id)
    markdown.lines.find { _1.start_with?("| `#{id}` |") }&.chomp
  end
end

class ChecklistNamedTestsTest < Minitest::Test
  KNOWN = %w[getJournal getJournals postJournals].freeze

  def scan(source)
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "test/resources"))
      File.write(File.join(root, "test/resources/journals_test.rb"), source)
      Checklist::NamedTests.scan(root: root, known: KNOWN)
    end
  end

  def test_a_marker_above_a_test_names_that_operation
    named = scan(<<~RUBY)
      class JournalsTest < Minitest::Test
        # names: getJournal
        def test_find
        end
      end
    RUBY

    assert_equal({ "getJournal" => ["test/resources/journals_test.rb#test_find"] }, named)
  end

  def test_several_markers_and_comments_can_sit_above_one_test
    named = scan(<<~RUBY)
      # names: getJournals
      # The list follows next_cursor.
      # names: postJournals
      def test_list_and_create
      end
    RUBY

    assert_equal %w[getJournals postJournals], named.keys.sort
  end

  def test_one_operation_can_be_named_by_several_tests
    named = scan(<<~RUBY)
      # names: getJournal
      def test_find
      end

      # names: getJournal
      def test_find_missing
      end
    RUBY

    assert_equal ["test/resources/journals_test.rb#test_find",
                  "test/resources/journals_test.rb#test_find_missing"], named["getJournal"]
  end

  def test_refuses_a_marker_that_is_not_directly_above_a_test
    error = assert_raises(Checklist::Error) { scan("# names: getJournal\n\ndef test_find\nend\n") }

    assert_match(%r{test/resources/journals_test.rb:1}, error.message)
  end

  def test_refuses_a_marker_left_at_the_end_of_a_file
    assert_raises(Checklist::Error) { scan("def test_find\nend\n# names: getJournal\n") }
  end

  def test_refuses_a_malformed_marker_instead_of_ignoring_it
    ["# names: getJournal getJournals", "# names: getJournal, getJournals", "# Names: getJournal"].each do |marker|
      assert_raises(Checklist::Error, marker) { scan("#{marker}\ndef test_find\nend\n") }
    end
  end

  def test_the_same_marker_twice_lists_the_test_once
    named = scan("# names: getJournal\n# names: getJournal\ndef test_find\nend\n")

    assert_equal ["test/resources/journals_test.rb#test_find"], named["getJournal"]
  end

  def test_refuses_an_operation_id_the_snapshot_does_not_have
    error = assert_raises(Checklist::Error) { scan("# names: getJurnal\ndef test_find\nend\n") }

    assert_match(/getJurnal/, error.message)
  end

  def test_only_reads_behaviour_tests_under_test_resources
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "test/tools"))
      File.write(File.join(root, "test/tools/contract_test.rb"), "# names: getJournal\ndef test_x\nend\n")

      assert_empty Checklist::NamedTests.scan(root: root, known: KNOWN)
    end
  end
end

class ChecklistRenderTest < Minitest::Test
  include ChecklistFixtures

  def test_every_live_operation_starts_registered_unnamed_and_unverified
    assert_equal "| `getJournal` | GET | `/journals/{id}` | yes | no | unverified: no sandbox access |  |",
                 row(render, "getJournal")
  end

  def test_the_deprecated_operation_is_skipped_in_the_live_column
    assert_includes row(render, "postLedgerAttachments"), "| skipped: deprecated |"
  end

  def test_named_comes_from_the_behaviour_tests_with_the_test_that_proves_it
    markdown = render(named: { "getJournal" => ["test/resources/journals_test.rb#test_find"] })

    assert_equal "| `getJournal` | GET | `/journals/{id}` | yes | yes | unverified: no sandbox access | " \
                 "`test/resources/journals_test.rb#test_find` |", row(markdown, "getJournal")
  end

  def test_an_operation_missing_from_the_table_is_not_registered
    assert_includes row(render(registered: %w[getJournals]), "getJournal"), "| no | no |"
  end

  def test_groups_rows_by_resource_group_in_path_order
    headings = render.lines.grep(/^## /).map(&:chomp)
    journal_rows = render.lines.grep(/^\| `(getJournal|getJournals|postJournals)`/)

    assert_equal ["## Journals (0 of 3 named)", "## Ledger Attachments (0 of 0 named)"], headings
    assert_equal(%w[getJournals postJournals getJournal], journal_rows.map { _1[/`(\w+)`/, 1] })
  end

  def test_the_summary_counts_live_operations_only_for_named
    markdown = render(named: { "getJournal" => ["t#test_a"] })

    assert_includes markdown, "| In the snapshot | 4 |"
    assert_includes markdown, "| Live (not deprecated) | 3 |"
    assert_includes markdown, "| Registered | 4 |"
    assert_includes markdown, "| Named | 1 of 3 live |"
    assert_includes markdown, "| Live-verified | 0 of 3 live |"
  end

  def test_names_its_sources_and_says_it_is_generated
    markdown = render

    assert_includes markdown, "docs/api/contract/2026-09-30/operations.json"
    assert_match(/Do not edit by hand/, markdown)
    assert_includes markdown, "Contract snapshot of 2026-09-30"
  end

  def test_the_same_inputs_render_byte_identical
    reordered = document.merge("operations" => document["operations"].reverse)

    assert_equal render, Checklist.render(reordered, source: "docs/api/contract/2026-09-30/operations.json",
                                                     registered: registered.reverse, named: {})
  end
end
