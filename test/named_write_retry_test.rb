# frozen_string_literal: true

require "test_helper"
require "stringio"

# Every named write (every named method whose Operation is not a GET) takes
# `retry:`, the same opt-in `client.call` takes (proposal 0001, D5 and D11).
#
# The test finds the writes by calling every public method of every
# resource class once and reading the verb it sends, so a new write is
# checked without being listed here. Then it calls each write again with
# `retry: :always` and checks, at the transport:
#
# - the Request carries `retry_policy: :always`. The Retry middleware
#   hands the transport the Request it was given, and reads nothing else to
#   decide whether a write may be sent again;
# - `retry` is in neither the body nor the query.
class NamedWriteRetryTest < Minitest::Test
  WRITES = 86
  ANSWER = '{"id":1,"status":"ready","items":[],"has_more":false,"next_cursor":null}'
  # Positional arguments that are not an id.
  ARGUMENTS = {
    file: -> { StringIO.new("%PDF-1.7") },
    categories: -> { [{ id: 1, weight: "1" }] },
    ledger_entry_lines: -> { [1, 2] }
  }.freeze

  # Records each Request, with its body read at send time: the Executor
  # closes a Multipart once the call is over.
  class Recorder
    Sent = Struct.new(:request, :body)

    attr_reader :sent

    def initialize = @sent = []

    def call(request)
      @sent << Sent.new(request, body_of(request.body))
      PennylaneClient::Response.new(status: 200, headers: {}, body: ANSWER)
    end

    private

    def body_of(body)
      return body unless body.respond_to?(:read)

      body.read.tap { body.rewind }
    end
  end

  def resources
    PennylaneClient::Resources.constants.map { PennylaneClient::Resources.const_get(_1) }
                              .select { _1.is_a?(Class) && _1 < PennylaneClient::Resources::Resource }
  end

  def client(recorder)
    PennylaneClient.new(token: "tok", transport: recorder, limiters: PennylaneClient::LimiterRegistry.new)
  end

  # Calls `name` on the resource `klass` with made-up required arguments,
  # plus `extra` keywords, and returns what reached the transport.
  def send_once(klass, name, **extra)
    recorder = Recorder.new
    resource = klass.new(client(recorder))
    positional, keywords = arguments(klass.instance_method(name))
    result = resource.public_send(name, *positional, **keywords, **extra)
    result.to_a if result.is_a?(Enumerator::Lazy)
    recorder.sent
  end

  def arguments(method)
    positional = method.parameters.select { _1.first == :req }.map { |_, name| ARGUMENTS.fetch(name, -> { 1 }).call }
    keywords = method.parameters.select { _1.first == :keyreq }.to_h { |_, name| [name, "x"] }
    [positional, keywords]
  end

  # [[Resources class, method name], ...] for every named method whose
  # first request is not a GET.
  def writes
    @writes ||= resources.flat_map do |klass|
      klass.public_instance_methods(false).filter_map do |name|
        [klass, name] unless send_once(klass, name).first.request.verb == :get
      end
    end
  end

  def label(klass, name) = "#{klass.name.split("::").last}##{name}"

  def test_finds_every_named_write
    assert_equal WRITES, writes.size, writes.map { label(*_1) }.join(", ")
  end

  def test_every_named_write_declares_retry
    missing = writes.reject { |klass, name| klass.instance_method(name).parameters.include?(%i[key retry]) }

    assert_empty missing.map { label(*_1) }, "named writes without an explicit `retry:` keyword"
  end

  def test_retry_always_reaches_the_retry_middleware_and_never_pennylane
    writes.each do |klass, name|
      write = send_once(klass, name, retry: :always).reject { _1.request.verb == :get }

      refute_empty write, label(klass, name)
      write.each { assert_opted_in(_1, label(klass, name)) }
    end
  end

  def assert_opted_in(sent, label)
    assert_equal :always, sent.request.retry_policy, label
    refute_match(/retry/, sent.body.to_s, "#{label} sent retry in the body")
    refute_match(/retry/, sent.request.url, "#{label} sent retry in the query")
  end

  def test_without_retry_a_named_write_keeps_the_default_policy
    writes.each do |klass, name|
      policies = send_once(klass, name).reject { _1.request.verb == :get }.map { _1.request.retry_policy }

      assert_equal [:default], policies.uniq, label(klass, name)
    end
  end

  def test_a_named_write_refuses_an_unknown_retry_policy
    klass, name = writes.first

    assert_raises(ArgumentError) { send_once(klass, name, retry: true) }
  end
end
