# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "date"
require "logger"
require "pathname"
require "stringio"
require "time"
require "tmpdir"
require "support/contract_stub"
require "support/doc_examples"
require "support/doc_setups"

# Runs every Ruby example in the user documentation, so the docs cannot
# drift from the gem.
#
# Why: a reader copies these examples. A method renamed, an argument
# changed, a field Pennylane does not take or a `# =>` value that is no
# longer true must fail the gate, not the reader. Each block tagged
# `<!-- example -->` in the files below runs against ContractStub, which
# answers with the examples in the contract snapshot and records any
# request, query field or body field the snapshot does not document.
class DocsExamplesTest < Minitest::Test
  include DocSetups

  DOCS = %w[README.md docs/getting-started.md docs/how-to.md].freeze
  FILES = %w[receipt.pdf timesheet.pdf invoice.pdf facturx.pdf po-1042.pdf invoice.xml].freeze

  def test_every_ruby_block_is_an_example_or_says_why_not
    unmarked = DOCS.flat_map { DocExamples.unmarked(_1) }

    assert_empty unmarked, "tag each with <!-- example --> or <!-- not run: reason -->"
  end

  def test_every_link_to_a_heading_finds_it
    assert_empty(DOCS.flat_map { DocExamples.broken_anchors(_1) })
  end

  def test_the_readme_examples_run = assert_examples_run("README.md")
  def test_the_getting_started_examples_run = assert_examples_run("docs/getting-started.md")
  def test_the_how_to_examples_run = assert_examples_run("docs/how-to.md")

  # The stub must catch what the docs could get wrong, or a green run
  # proves nothing.
  def test_the_contract_stub_flags_what_the_snapshot_does_not_document
    stub_contract
    client = PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
    client.customer_invoices.list(filter: [{ field: "status", operator: "eq", value: "draft" }]).first
    client.customer_invoices.create(customer_id: 1, invoice_lines: [{ label: "Audit", colour: "blue" }])
    client.call(:getMe, page: 2)

    assert_equal ["getCustomerInvoices (GET /api/external/v2/customer_invoices) " \
                  "does not list \"status\" as a filter field",
                  "postCustomerInvoices (POST /api/external/v2/customer_invoices) " \
                  "declares no field body.invoice_lines[].colour",
                  "getMe (GET /api/external/v2/me) takes no query parameter \"page\""], @contract.violations
  end

  def test_a_result_comment_is_checked
    example = DocExamples::Example.new("README.md", 10, "x = 1\nx + 1   # => 3, the sum\n", [])

    assert_equal "x = 1\nexpect_result((x + 1), 3, 11)\n", example.checked_code
    assert_raises(Minitest::Assertion) { DocExamples::Sandbox.new(nil).run(example) }
  end

  private

  def assert_examples_run(file)
    examples = DocExamples.examples(file)
    refute_empty examples

    failures = in_workdir { run_all(examples) }

    assert failures.empty?, failures.join("\n\n")
  end

  def run_all(examples)
    sandbox = nil
    examples.each_with_index.filter_map do |example, index|
      sandbox = new_sandbox(index) unless example.continued? && sandbox
      failure_of(example, sandbox)
    end
  end

  # A token of its own for each scope, so the examples that build their own
  # client never share a rate-limit window.
  def new_sandbox(index)
    ENV["PENNYLANE_TOKEN"] = "docs-token-#{index}-#{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}"
    limiters = PennylaneClient::LimiterRegistry.new { DocExamples::Unlimited.new }
    DocExamples::Sandbox.new(PennylaneClient.new(token: ENV.fetch("PENNYLANE_TOKEN"), limiters:))
  end

  # nil when the example ran, sent only documented requests and passed its
  # setup's check; else what went wrong, with its file and line.
  def failure_of(example, sandbox)
    violations = run_one(example, sandbox)
    "#{example.label}: requests the contract does not document:\n  #{violations.join("\n  ")}" if violations.any?
  rescue StandardError, ScriptError, Minitest::Assertion => e
    "#{example.label}: #{e.class}: #{e.message}\n  #{e.backtrace.grep(/#{Regexp.escape(example.file)}/).first}"
  ensure
    PennylaneClient.configuration.logger = nil
    PennylaneClient.configuration.on_request = nil
  end

  # Returns the contract violations.
  def run_one(example, sandbox)
    stub_contract
    check = prepare(example.setup, sandbox)
    capture_io { sandbox.run(example) }
    check&.call(sandbox)
    @contract.violations
  end

  def stub_contract
    WebMock.reset!
    contract = @contract = ContractStub.new
    stub_request(:any, %r{\Ahttps://app\.pennylane\.com/}).to_return { |request| contract.respond(request) }
  end

  def in_workdir(&)
    Dir.mktmpdir("pennylane-docs") do |dir|
      FILES.each { File.write(File.join(dir, _1), _1.end_with?(".xml") ? "<Invoice/>" : "%PDF-1.4\n%%EOF\n") }
      Dir.chdir(dir, &)
    end
  end
end
