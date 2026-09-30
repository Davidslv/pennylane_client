# frozen_string_literal: true

require "test_helper"
require_relative "../tools/operation_table"

# The contract test: the generated table against the snapshot it came from.
# A sanity check only, because the table is generated from that snapshot.
# It never counts towards `named` in the checklist; behaviour tests do.
class OperationsTest < Minitest::Test
  CONTRACT = File.expand_path("../docs/api/contract", __dir__)

  def snapshot
    @snapshot ||= JSON.parse(File.read(OperationTable.latest_snapshot(CONTRACT))).fetch("operations")
  end

  def test_registers_every_operation_in_the_snapshot_once
    ids = PennylaneClient::OPERATIONS.map(&:id)

    assert_equal ids.uniq, ids
    assert_equal snapshot.map { _1["operation_id"].to_sym }.sort, ids.sort
  end

  def test_carries_the_deprecated_flag_for_every_operation
    deprecated = snapshot.select { _1["deprecated"] }.map { _1["operation_id"].to_sym }

    assert_equal deprecated.sort, PennylaneClient::OPERATIONS.select(&:deprecated).map(&:id).sort
  end

  def test_is_a_frozen_table_of_operations
    assert_predicate PennylaneClient::OPERATIONS, :frozen?
    assert(PennylaneClient::OPERATIONS.all?(PennylaneClient::Operation))
  end
end
