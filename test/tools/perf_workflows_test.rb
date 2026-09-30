# frozen_string_literal: true

require_relative "../test_helper"
require "yaml"

# rake load runs on every pull request and push to main; rake stress runs on
# demand, with an optional soak.
class PerfWorkflowsTest < Minitest::Test
  WORKFLOWS = File.expand_path("../../.github/workflows", __dir__)

  def workflow(name) = YAML.safe_load_file(File.join(WORKFLOWS, name))

  # YAML 1.1 reads the bare key `on` as true.
  def triggers(workflow) = workflow.fetch(true) { workflow.fetch("on") }

  def runs(job) = job.fetch("steps").filter_map { _1["run"] }

  def test_ci_runs_rake_load_on_every_pull_request
    ci = workflow("ci.yml")
    load = ci.fetch("jobs").fetch("load")

    assert triggers(ci).key?("pull_request")
    assert_includes runs(load), "bundle exec rake load"
  end

  def test_stress_runs_only_on_demand_with_an_optional_soak
    stress = workflow("stress.yml")
    job = stress.fetch("jobs").fetch("stress")

    assert_equal ["workflow_dispatch"], triggers(stress).keys
    assert_equal "0", triggers(stress).dig("workflow_dispatch", "inputs", "soak_minutes", "default").to_s
    step = job.fetch("steps").find { _1["run"] == "bundle exec rake stress" }

    assert_equal "${{ inputs.soak_minutes }}", step.dig("env", "SOAK_MINUTES"), "the input never enters the script"
  end

  def test_stress_has_time_for_a_30_minute_soak_and_reads_nothing_it_does_not_need
    stress = workflow("stress.yml")

    assert_operator stress.dig("jobs", "stress", "timeout-minutes"), :>=, 45
    assert_equal({ "contents" => "read" }, stress.fetch("permissions"))
  end
end
