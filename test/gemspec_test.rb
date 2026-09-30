# frozen_string_literal: true

require "test_helper"

# Pins the packaging rules from proposal 0001 (D1, D4) so they cannot drift.
class GemspecTest < Minitest::Test
  def spec
    @spec ||= Gem::Specification.load(File.expand_path("../pennylane_client.gemspec", __dir__))
  end

  def test_version_is_semver
    assert_match(/\A\d+\.\d+\.\d+(\.[a-z0-9.]+)?\z/, PennylaneClient::VERSION)
  end

  def test_has_zero_runtime_dependencies
    assert_empty spec.runtime_dependencies, "pennylane_client must stay stdlib-only"
  end

  def test_requires_a_supported_ruby
    assert_equal Gem::Requirement.new(">= 3.3"), spec.required_ruby_version
  end

  def test_declares_itself_unofficial
    assert_match(/unofficial/i, spec.summary)
    assert_match(/not affiliated with Pennylane/i, spec.description)
  end

  def test_requires_mfa_and_points_at_the_repo
    assert_equal "true", spec.metadata["rubygems_mfa_required"]
    %w[homepage_uri source_code_uri changelog_uri bug_tracker_uri].each do |key|
      assert_match %r{\Ahttps://github.com/Davidslv/pennylane_client}, spec.metadata[key], key
    end
  end

  def test_ships_only_library_code_and_legal_files
    allowed = %r{\A(lib/|sig/|README\.md\z|LICENSE\.txt\z|CHANGELOG\.md\z)}
    offenders = spec.files.grep_v(allowed)

    assert_empty offenders, "unexpected files in the gem: #{offenders.join(", ")}"
    assert_includes spec.files, "lib/pennylane_client.rb"
    assert_includes spec.files, "sig/pennylane_client.rbs"
  end
end
