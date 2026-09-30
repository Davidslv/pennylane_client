# frozen_string_literal: true

require_relative "../test_helper"
require "yaml"

# The drift workflow's shape: when it runs, what it may touch, what it runs.
class ContractDriftWorkflowTest < Minitest::Test
  PATH = File.expand_path("../../.github/workflows/contract-drift.yml", __dir__)

  def workflow
    @workflow ||= YAML.safe_load_file(PATH)
  end

  # YAML 1.1 reads the bare key `on` as true.
  def triggers
    workflow.fetch(true) { workflow.fetch("on") }
  end

  def steps
    workflow.fetch("jobs").fetch("drift").fetch("steps")
  end

  def test_runs_weekly_and_on_demand
    assert_equal [{ "cron" => "0 6 * * 1" }], triggers.fetch("schedule")
    assert triggers.key?("workflow_dispatch")
  end

  def test_has_least_privilege_permissions
    assert_equal({ "contents" => "read", "issues" => "write" }, workflow.fetch("permissions"))
    refute workflow.fetch("jobs").fetch("drift").key?("permissions"), "no job-level widening"
  end

  def test_runs_the_drift_tool_with_the_workflow_token
    step = steps.find { _1["run"] }

    assert_equal "ruby tools/contract_drift.rb --open-issue", step.fetch("run")
    assert_equal "${{ github.token }}", step.fetch("env").fetch("GH_TOKEN")
  end

  def test_never_commits_or_keeps_git_credentials
    checkout = steps.find { _1["uses"]&.start_with?("actions/checkout@") }

    refute checkout.fetch("with").fetch("persist-credentials")
    steps.filter_map { _1["run"] }.each { refute_match(/\bgit\b/, _1) }
  end
end
