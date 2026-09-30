# frozen_string_literal: true

require "test_helper"

class RegistryTest < Minitest::Test
  JOURNAL = PennylaneClient::Operation.new(
    id: :getJournal, verb: :get, path: "/api/external/v2/journals/{id}",
    paginated: false, max_limit: nil, body: nil, success: 200, deprecated: false
  )

  def registry = PennylaneClient::Registry.new([JOURNAL])

  def test_finds_an_operation_by_its_operation_id
    assert_equal JOURNAL, registry.fetch(:getJournal)
    assert_equal JOURNAL, registry.fetch("getJournal")
  end

  def test_raises_on_an_unknown_operation_id
    error = assert_raises(PennylaneClient::UnknownOperationError) { registry.fetch(:getJournalz) }

    assert_kind_of ArgumentError, error
    assert_equal "unknown operation :getJournalz", error.message
  end

  def test_is_frozen
    assert_predicate registry, :frozen?
  end

  def test_the_default_registry_holds_every_registered_operation
    default = PennylaneClient::Registry.default

    assert_same default, PennylaneClient::Registry.default
    assert_equal PennylaneClient::OPERATIONS.size, default.size
    assert_equal :deleteLedgerEntryLinesUnletter, default.fetch(:deleteLedgerEntryLinesUnletter).id
  end
end
