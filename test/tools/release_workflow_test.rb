# frozen_string_literal: true

require_relative "../test_helper"
require "yaml"

# The release workflow's shape: Trusted Publishing on a v* tag, with a
# Sigstore attestation, only after the gate passes (proposal 0001).
class ReleaseWorkflowTest < Minitest::Test
  PATH = File.expand_path("../../.github/workflows/release.yml", __dir__)

  def workflow
    @workflow ||= YAML.safe_load_file(PATH)
  end

  # YAML 1.1 reads the bare key `on` as true.
  def triggers
    workflow.fetch(true) { workflow.fetch("on") }
  end

  def job
    workflow.fetch("jobs").fetch("release")
  end

  def steps
    job.fetch("steps")
  end

  def test_runs_only_on_a_version_tag
    assert_equal({ "push" => { "tags" => ["v*"] } }, triggers)
  end

  def test_reads_by_default_and_widens_only_the_release_job
    assert_equal({ "contents" => "read" }, workflow.fetch("permissions"))
    assert_equal({ "contents" => "write", "id-token" => "write" }, job.fetch("permissions"))
  end

  def test_runs_in_the_release_environment
    assert_equal "release", job.fetch("environment")
  end

  def test_refuses_a_tag_that_does_not_match_the_gem_version
    step = steps.find { _1["name"]&.include?("tag matches") }

    assert_equal "${{ github.ref_name }}", step.fetch("env").fetch("TAG"), "the tag never enters the script"
    assert_includes step.fetch("run"), "PennylaneClient::VERSION"
  end

  def test_runs_the_gate_before_publishing
    runs = steps.map { _1["run"] }
    publish = steps.index { _1["uses"]&.start_with?("rubygems/release-gem@") }

    assert_operator runs.index("bundle exec rake"), :<, publish
  end

  def test_installs_the_built_gem_and_loads_it_outside_the_repo_before_publishing
    built = steps.index { _1["run"].to_s.include?("gem install --local") }
    publish = steps.index { _1["uses"]&.start_with?("rubygems/release-gem@") }

    refute_nil built
    run = steps[built].fetch("run")

    assert_includes run, "gem build pennylane_client.gemspec"
    assert_includes run, 'cd "$RUNNER_TEMP"'
    assert_operator built, :<, publish
  end

  def test_never_keeps_git_credentials
    checkout = steps.find { _1["uses"]&.start_with?("actions/checkout@") }

    refute checkout.fetch("with").fetch("persist-credentials")
    steps.filter_map { _1["run"] }.each { refute_match(/\bgit\b/, _1) }
  end

  def test_publishes_by_trusted_publishing_with_an_attestation
    step = steps.find { _1["uses"]&.start_with?("rubygems/release-gem@") }

    assert_equal "rubygems/release-gem@v1", step.fetch("uses")
    assert step.fetch("with").fetch("attestations")
    steps.each { refute_match(/RUBYGEMS_API_KEY|GEM_HOST_API_KEY/, _1.to_s) }
  end
end
