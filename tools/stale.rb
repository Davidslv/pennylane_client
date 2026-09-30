# frozen_string_literal: true

# Fail when a generated file differs from what its generator writes.
#
# Why: the operation table and the checklist are only trustworthy if nobody
# edits them by hand and nobody forgets to regenerate them. This regenerates
# both in memory and compares, so `bundle exec rake` catches a hand edit or
# a missed `rake contract:sync checklist` before CI does.
#
# Standard library only. Run it with `bundle exec rake stale`.

require_relative "operation_table"
require_relative "checklist"

# Compares the committed generated files with fresh generator output.
module Stale
  TABLE = "lib/pennylane_client/operations.rb"
  CHECKLIST = "docs/api/CHECKLIST.md"

  # What each generated file should hold, keyed by its path under root.
  def self.expected(root:, registered:)
    {
      TABLE => OperationTable.generate(contract_root: File.join(root, "docs/api/contract"), relative_to: root),
      CHECKLIST => Checklist.generate(root: root, registered: registered)
    }
  end

  # The generated files that are missing or differ from their generator.
  def self.differences(root:, registered:)
    expected(root: root, registered: registered).reject do |path, content|
      file = File.join(root, path)
      File.file?(file) && File.read(file) == content
    end.keys
  end
end

if $PROGRAM_NAME == __FILE__
  require_relative "../lib/pennylane_client"

  stale = Stale.differences(root: File.expand_path("..", __dir__),
                            registered: PennylaneClient::OPERATIONS.map { _1.id.to_s })
  abort "Stale generated files: #{stale.join(", ")}. Run `bundle exec rake contract:sync checklist`." if stale.any?
  puts "Generated files are current."
end
