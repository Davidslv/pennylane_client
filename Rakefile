# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "rubocop/rake_task"

RuboCop::RakeTask.new

desc "Validate the RBS signatures in sig/"
task :rbs do
  sh "rbs", "-I", "sig", "validate"
end

namespace :contract do
  desc "Snapshot the Pennylane API contract into docs/api/contract/<date>/ (reaches pennylane.readme.io)"
  task :snapshot do
    ruby "tools/snapshot_contract.rb"
  end

  desc "Regenerate lib/pennylane_client/operations.rb from the latest contract snapshot"
  task :sync do
    ruby "tools/operation_table.rb"
  end
end

desc "Regenerate docs/api/CHECKLIST.md from the snapshot, the operation table and the behaviour tests"
task :checklist do
  ruby "tools/checklist.rb"
end

task default: %i[test rubocop rbs]
