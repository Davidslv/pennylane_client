# frozen_string_literal: true

require_relative "../../tools/checklist"

# Checks that a behaviour test sends every Operation its `# names:` markers
# name.
#
# Why: a marker counts an Operation as Named in docs/api/CHECKLIST.md. The
# checklist generator reads markers from the source and cannot see what the
# test does, so a marker above `assert true` would count. Here the suite
# records the operationId of every Request that reaches the transport while
# a test under test/resources/ runs, and fails the test when an id its
# markers name was not sent. The gate runs the suite, so a marker the gate
# lets through is one whose test sends the Operation.
#
# Only a passing test is checked, so a real failure is not buried under a
# second one.
module NamedTrace
  RESOURCE_TEST = %r{/test/resources/[^/]+_test\.rb\z}

  @sent = []
  @markers = {}

  class << self
    attr_reader :sent

    # The operationIds the markers above `test` in `file` name.
    def marked(file, test)
      @markers[file] ||= Checklist::NamedTests.markers(File.read(file), file)
      @markers[file].fetch(test, [])
    end
  end

  # Records each Request that reaches the transport.
  module Recording
    def call(request)
      NamedTrace.sent << request.operation_id.to_s
      super
    end
  end

  # Clears the record before each test and checks it after.
  module Check
    def before_setup
      NamedTrace.sent.clear
      super
    end

    def after_teardown
      super
      return unless passed?

      file = method(name).source_location.first
      return unless RESOURCE_TEST.match?(file)

      NamedTrace.marked(file, name).each do |id|
        assert_includes NamedTrace.sent, id, "#{name} names #{id} but did not send it"
      end
    end
  end
end

PennylaneClient::NetHttpTransport.prepend(NamedTrace::Recording)
Minitest::Test.include(NamedTrace::Check)
