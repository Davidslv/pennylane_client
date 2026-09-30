# frozen_string_literal: true

require "json"
require_relative "contract_check"
require_relative "contract_examples"

# Answers any request to Pennylane with the example the contract snapshot
# documents for its Operation, and records every way the request strays
# from the contract.
#
# Why: the documentation examples (test/docs_examples_test.rb) run against
# it. Each answer is built from the snapshot's own schema and examples
# (ContractExamples), so an example shows the data shape Pennylane
# documents. Each request is checked against the same snapshot
# (ContractCheck); a request to no Operation is a violation too, and the
# docs test fails on any.
class ContractStub
  ROOT = File.expand_path("../..", __dir__)

  # One documented Operation: the snapshot entry and a pattern for its path.
  Entry = Struct.new(:spec, :pattern, :placeholders)

  attr_reader :violations

  def initialize
    snapshot = Dir.glob(File.join(ROOT, "docs/api/contract/*/operations.json")).max
    operations = JSON.parse(File.read(snapshot)).fetch("operations")
    @entries = operations.map { entry(_1) }.sort_by(&:placeholders)
    @violations = []
  end

  # The WebMock response for `request`, a WebMock::RequestSignature.
  def respond(request)
    found = find(request)
    unless found
      @violations << "#{request.method.to_s.upcase} #{request.uri.path} is no Operation in the contract snapshot"
      return { status: 404, body: "" }
    end

    @violations.concat(ContractCheck.new(found.spec).violations(request))
    answer(found.spec)
  end

  # The documented success body of `operation_id`, from Pennylane's example.
  def body_for(operation_id)
    entry = @entries.find { _1.spec["operation_id"] == operation_id.to_s }
    raise ArgumentError, "no operation #{operation_id}" unless entry

    success_body(entry.spec)
  end

  private

  def entry(spec)
    source = Regexp.escape(spec.fetch("path")).gsub(/\\\{\w+\\\}/, "[^/]+")
    Entry.new(spec, /\A#{source}\z/, spec.fetch("path").scan(/\{\w+\}/).size)
  end

  # The literal path wins over a template: /customer_invoices/import
  # before /customer_invoices/{id}.
  def find(request)
    verb = request.method.to_s.upcase
    @entries.find { _1.spec.fetch("method") == verb && _1.pattern.match?(request.uri.path) }
  end

  def answer(spec)
    status = Integer(spec.fetch("responses").keys.grep(/\A2/).first)
    body = status == 204 ? "" : JSON.generate(success_body(spec))
    { status:, body:, headers: { "Content-Type" => "application/json" } }
  end

  # A list page ends at once, so a walk reads one page.
  def success_body(spec)
    response = spec.fetch("responses").find { |status, _| status.start_with?("2") }.last
    body = ContractExamples.example(response.dig("content", "application/json", "schema"))
    body = body.merge("has_more" => false, "next_cursor" => nil) if body.is_a?(Hash) && body.key?("items")
    body
  end
end
