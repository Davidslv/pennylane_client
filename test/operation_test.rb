# frozen_string_literal: true

require "test_helper"

class OperationTest < Minitest::Test
  def row(**overrides)
    PennylaneClient::Operation.new(
      id: :getJournal, verb: :get, path: "/api/external/v2/journals/{id}",
      paginated: false, body: nil, success: 200, deprecated: false, **overrides
    )
  end

  def test_holds_what_the_executor_needs_to_build_a_request
    operation = row

    assert_equal :getJournal, operation.id
    assert_equal :get, operation.verb
    assert_equal "/api/external/v2/journals/{id}", operation.path
    refute operation.paginated
    assert_nil operation.body
    assert_equal 200, operation.success
    refute operation.deprecated
  end

  def test_is_an_immutable_value
    assert_predicate row, :frozen?
    assert_equal row, row
    refute_equal row, row(verb: :post)
  end

  def test_refuses_a_row_with_a_missing_field
    assert_raises(ArgumentError) { PennylaneClient::Operation.new(id: :getJournal, verb: :get) }
  end
end
