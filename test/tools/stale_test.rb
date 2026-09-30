# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tools/stale"
require "tmpdir"

class StaleTest < Minitest::Test
  RECORD = {
    "operation_id" => "getJournal", "method" => "GET", "path" => "/api/external/v2/journals/{id}",
    "tags" => ["Journals"], "deprecated" => false, "parameters" => [], "request_body" => nil,
    "responses" => { "200" => {} }
  }.freeze

  # A throwaway repo with a one-operation snapshot and freshly generated files.
  def with_repo
    Dir.mktmpdir do |root|
      write(root, "docs/api/contract/2026-09-30/operations.json",
            JSON.generate("retrieved_on" => "2026-09-30", "operations" => [RECORD]))
      write(root, Stale::README, "# gem\n\n#{Checklist::Readme::START}\ntyped\n#{Checklist::Readme::FINISH}\n")
      Stale.expected(root: root, registered: %w[getJournal]).each { |path, content| write(root, path, content) }
      yield root
    end
  end

  def write(root, path, content)
    FileUtils.mkdir_p(File.dirname(File.join(root, path)))
    File.write(File.join(root, path), content)
  end

  def stale(root)
    Stale.differences(root: root, registered: %w[getJournal])
  end

  def test_freshly_generated_files_are_not_stale
    with_repo { |root| assert_empty stale(root) }
  end

  def test_a_hand_edited_operation_table_is_stale
    with_repo do |root|
      table = File.join(root, Stale::TABLE)
      File.write(table, File.read(table).sub("success: 200", "success: 201"))

      assert_equal [Stale::TABLE], stale(root)
    end
  end

  def test_a_hand_ticked_checklist_is_stale
    with_repo do |root|
      checklist = File.join(root, Stale::CHECKLIST)
      File.write(checklist, File.read(checklist).sub("| yes | no |", "| yes | yes |"))

      assert_equal [Stale::CHECKLIST], stale(root)
    end
  end

  def test_a_new_behaviour_test_makes_the_checklist_stale_until_regenerated
    with_repo do |root|
      write(root, "test/resources/journals_test.rb", "# names: getJournal\ndef test_find\nend\n")

      assert_equal [Stale::CHECKLIST], stale(root)
    end
  end

  def test_a_hand_typed_readme_count_is_stale
    with_repo do |root|
      readme = File.join(root, Stale::README)
      File.write(readme, File.read(readme).sub("0 of 1", "1 of 1"))

      assert_equal [Stale::README], stale(root)
    end
  end

  def test_a_new_sandbox_report_makes_the_checklist_and_readme_stale_until_regenerated
    with_repo do |root|
      write(root, "docs/api/live/2026-10-01-octocat.json",
            JSON.generate("format" => 1, "verified_on" => "2026-10-01", "by" => "octocat",
                          "operations" => { "getJournal" => "pass" }))

      assert_equal [Stale::CHECKLIST, Stale::README], stale(root)
    end
  end

  def test_a_missing_generated_file_is_stale
    with_repo do |root|
      File.delete(File.join(root, Stale::TABLE))

      assert_equal [Stale::TABLE], stale(root)
    end
  end
end
