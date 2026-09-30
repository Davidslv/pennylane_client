# frozen_string_literal: true

require "test_helper"

# The README quotes operation counts; CHECKLIST.md is generated from the
# snapshot. A new snapshot that changes the count fails here until the
# README catches up.
class ReadmeTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def readme = File.read(File.join(ROOT, "README.md"))

  def checklist = File.read(File.join(ROOT, "docs/api/CHECKLIST.md"))

  def checklist_count(row)
    Integer(checklist[/^\| #{Regexp.escape(row)} \| (\d+)/, 1])
  end

  def test_every_live_operation_count_matches_the_checklist
    live = checklist_count("Live (not deprecated)")
    quoted = readme.scan(/(\d+)\**\s+live operations/).flatten.map { Integer(_1) }

    refute_empty quoted
    assert_equal [live], quoted.uniq
  end

  def test_says_every_live_operation_is_named_only_when_the_checklist_does
    live = checklist_count("Live (not deprecated)")

    assert_includes readme, "Every live operation has a named method"
    assert_match(/^\| Named \| #{live} of #{live} live \|$/, checklist)
  end
end
