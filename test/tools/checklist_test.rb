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

  def render(named: {}, registered: self.registered, live: Checklist::LiveReports::NONE)
    Checklist.render(document, source: "docs/api/contract/2026-09-30/operations.json",
                               registered: registered, named: named, live: live)
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

class ChecklistLiveReportsTest < Minitest::Test
  KNOWN = %w[getJournal getJournals postJournals].freeze

  def report(on, by, operations, checks: {})
    { "format" => 1, "verified_on" => on, "by" => by, "contract" => "2026-09-30",
      "operations" => operations, "checks" => checks }
  end

  def scan(*reports)
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "docs/api/live"))
      reports.each_with_index do |content, index|
        File.write(File.join(root, "docs/api/live/report-#{index}.json"), JSON.generate(content))
      end
      Checklist::LiveReports.scan(root: root, known: KNOWN)
    end
  end

  def test_no_report_folder_means_nothing_is_verified
    Dir.mktmpdir do |root|
      assert_equal Checklist::LiveReports::NONE, Checklist::LiveReports.scan(root: root, known: KNOWN)
    end
  end

  def test_only_passed_operations_are_verified
    live = scan(report("2026-10-01", "octocat", { "getJournal" => "pass", "getJournals" => "fail: 403" }))

    assert_equal({ "getJournal" => %w[2026-10-01 octocat] }, live.verified)
  end

  def test_the_latest_report_that_ran_an_operation_decides
    live = scan(report("2026-10-05", "hubot", { "getJournal" => "fail: 500", "postJournals" => "pass" }),
                report("2026-10-01", "octocat", { "getJournal" => "pass", "getJournals" => "pass" }))

    assert_equal({ "getJournals" => %w[2026-10-01 octocat], "postJournals" => %w[2026-10-05 hubot] }, live.verified)
  end

  def test_a_later_report_that_did_not_run_an_operation_leaves_an_earlier_pass
    live = scan(report("2026-10-01", "octocat", { "getJournal" => "pass" }),
                report("2026-10-05", "hubot", { "getJournal" => "not run: 403 PermissionError" }))

    assert_equal({ "getJournal" => %w[2026-10-01 octocat] }, live.verified)
  end

  def test_a_report_on_an_older_contract_may_name_operations_the_snapshot_has_since_dropped
    old = report("2026-10-01", "octocat", { "getJournal" => "pass", "getRetired" => "pass" })
    old["contract"] = "2026-01-01"
    live = Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "docs/api/live"))
      File.write(File.join(root, "docs/api/live/old.json"), JSON.generate(old))
      Checklist::LiveReports.scan(root: root, known: KNOWN, contract: "2026-09-30")
    end

    assert_equal ["getJournal"], live.verified.keys
  end

  def test_refuses_a_result_that_is_not_a_string
    assert_raises(Checklist::Error) { scan(report("2026-10-01", "octocat", {}, checks: { "probe" => 1 })) }
    assert_raises(Checklist::Error) { scan(report("2026-10-01", "octocat", { "getJournal" => true })) }
  end

  def test_checks_keep_the_latest_result_that_actually_ran
    live = scan(report("2026-10-01", "octocat", {}, checks: { "webhook_signature" => "pass", "probe" => "pass" }),
                report("2026-10-05", "hubot", {}, checks: { "webhook_signature" => "not run",
                                                            "probe" => "not run: no customer in the sandbox" }))

    assert_equal({ "webhook_signature" => %w[pass 2026-10-01 octocat], "probe" => %w[pass 2026-10-01 octocat] },
                 live.checks)
  end

  def test_refuses_an_operation_id_the_snapshot_does_not_have
    error = assert_raises(Checklist::Error) { scan(report("2026-10-01", "octocat", { "getJurnal" => "pass" })) }

    assert_match(/getJurnal/, error.message)
  end

  def test_refuses_a_report_without_a_date_or_a_github_user
    [report("yesterday", "octocat", {}), report("2026-10-01", "not a user!", {}),
     report("2026-10-01", "octocat", {}).merge("format" => 2)].each do |bad|
      assert_raises(Checklist::Error, bad.inspect) { scan(bad) }
    end
  end
end

class ChecklistReadmeTest < Minitest::Test
  README = <<~MARKDOWN.freeze
    # gem

    #{Checklist::Readme::START}
    anything typed here
    #{Checklist::Readme::FINISH}

    ## Next
  MARKDOWN

  def test_replaces_only_the_marked_region_with_the_generated_count
    updated = Checklist::Readme.update(README, verified: 3, live: 177)

    assert_equal <<~MARKDOWN, updated
      # gem

      #{Checklist::Readme::START}
      Live-verified against a Pennylane sandbox: **3 of 177** live operations. The [checklist](docs/api/CHECKLIST.md) lists which, and [CONTRIBUTING.md](CONTRIBUTING.md#verifying-against-a-real-pennylane-sandbox) says how to add to it.
      #{Checklist::Readme::FINISH}

      ## Next
    MARKDOWN
  end

  def test_updating_twice_changes_nothing
    once = Checklist::Readme.update(README, verified: 0, live: 177)

    assert_equal once, Checklist::Readme.update(once, verified: 0, live: 177)
  end

  def test_refuses_a_readme_without_the_markers
    assert_raises(Checklist::Error) { Checklist::Readme.update("# gem\n", verified: 0, live: 177) }
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

  def test_a_sandbox_verified_operation_shows_the_date_and_the_contributor
    live = Checklist::LiveReports::Live.new(verified: { "getJournal" => %w[2026-10-01 octocat] }, checks: {})
    markdown = render(live: live)

    assert_includes row(markdown, "getJournal"), "| sandbox-verified 2026-10-01 (by @octocat) |"
    assert_includes row(markdown, "getJournals"), "| unverified: no sandbox access |"
    assert_includes markdown, "| Live-verified | 1 of 3 live |"
  end

  def test_a_deprecated_operation_stays_skipped_even_when_a_report_passes_it
    live = Checklist::LiveReports::Live.new(verified: { "postLedgerAttachments" => %w[2026-10-01 octocat] },
                                            checks: {})
    markdown = render(live: live)

    assert_includes row(markdown, "postLedgerAttachments"), "| skipped: deprecated |"
    assert_includes markdown, "| Live-verified | 0 of 3 live |"
  end

  def test_sandbox_checks_get_their_own_section_only_when_a_report_has_them
    refute_match(/## Sandbox checks/, render)

    checks = { "webhook_signature" => %w[pass 2026-10-01 octocat] }
    live = Checklist::LiveReports::Live.new(verified: {}, checks: checks)

    assert_includes render(live: live), "| `webhook_signature` | pass | 2026-10-01 (by @octocat) |"
  end

  def test_the_same_inputs_render_byte_identical
    reordered = document.merge("operations" => document["operations"].reverse)

    assert_equal render, Checklist.render(reordered, source: "docs/api/contract/2026-09-30/operations.json",
                                                     registered: registered.reverse, named: {})
  end
end
