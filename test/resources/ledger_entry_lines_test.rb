# frozen_string_literal: true

require "test_helper"

# Ledger entry lines: `client.ledger_entry_lines`. Each stub is the method
# and path from the operation's reference page.
class LedgerEntryLinesTest < Minitest::Test
  API = "https://app.pennylane.com/api/external/v2"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)
  def lines = client.ledger_entry_lines

  # One page of items with ids, the last one.
  def page(*ids) = JSON.generate({ items: ids.map { { id: _1 } }, has_more: false, next_cursor: nil })

  def test_is_one_resource_per_client
    assert_same client.ledger_entry_lines, client.ledger_entry_lines
    refute_includes client.ledger_entry_lines.inspect, "tok"
  end

  # names: getLedgerEntryLines
  def test_list_walks_every_page_resending_the_filter
    bank = [{ field: "ledger_account_id", operator: "eq", value: "512" }]
    query = { filter: JSON.generate(bank), sort: "-date", limit: "100" }
    first = JSON.generate({ items: [{ id: 1 }], has_more: true, next_cursor: "c2" })
    stub_request(:get, "#{API}/ledger_entry_lines").with(query:).to_return(status: 200, body: first)
    stub_request(:get, "#{API}/ledger_entry_lines").with(query: query.merge(cursor: "c2"))
                                                   .to_return(status: 200, body: page(2))

    assert_equal [1, 2], lines.list(filter: bank, sort: "-date").map { _1[:id] }.to_a
  end

  # names: getLedgerEntryLine
  def test_find
    stub_request(:get, "#{API}/ledger_entry_lines/91").to_return(status: 200, body: '{"id":91,"debit":"1200.00"}')

    assert_equal({ id: 91, debit: "1200.00" }, lines.find(91))
  end

  # names: postLedgerEntryLinesLetter
  def test_letter_returns_every_line_of_the_new_lettering
    body = { ledger_entry_lines: [{ id: 91 }, { id: 95 }], unbalanced_lettering_strategy: "none" }
    stub_request(:post, "#{API}/ledger_entry_lines/lettering").with(body: JSON.generate(body))
                                                              .to_return(status: 200, body: '[{"id":91},{"id":95}]')

    assert_equal [{ id: 91 }, { id: 95 }],
                 lines.letter([{ id: 91 }, { id: 95 }], unbalanced_lettering_strategy: "none")
  end

  # names: deleteLedgerEntryLinesUnletter
  def test_unletter_sends_a_body_with_the_delete
    body = { ledger_entry_lines: [{ id: 91 }], unbalanced_lettering_strategy: "partial" }
    stub_request(:delete, "#{API}/ledger_entry_lines/lettering").with(body: JSON.generate(body))
                                                                .to_return(status: 204)

    assert_same true, lines.unletter([{ id: 91 }], unbalanced_lettering_strategy: "partial")
  end

  # Pennylane answers 422 when the lettering would not balance under "none".
  def test_letter_unbalanced_raises_validation_error
    stub_request(:post, "#{API}/ledger_entry_lines/lettering")
      .to_return(status: 422, body: '{"error":"unprocessable_entity","message":"Lettering is unbalanced"}')

    assert_raises(PennylaneClient::ValidationError) do
      lines.letter([{ id: 91 }, { id: 95 }], unbalanced_lettering_strategy: "none")
    end
  end

  # names: getLedgerEntryLinesLetteredLedgerEntryLines
  def test_lettered_lines_walks_every_page
    stub_request(:get, "#{API}/ledger_entry_lines/91/lettered_ledger_entry_lines")
      .with(query: { sort: "date", limit: "100" }).to_return(status: 200, body: page(95, 96))

    assert_equal [95, 96], lines.lettered_lines(91, sort: "date").map { _1[:id] }.to_a
  end

  # names: getLedgerEntryLinesCategories
  def test_categories_walks_every_page
    stub_request(:get, "#{API}/ledger_entry_lines/91/categories").with(query: { limit: "100" })
                                                                 .to_return(status: 200, body: page(59, 33))

    assert_equal [59, 33], lines.categories(91).map { _1[:id] }.to_a
  end

  # names: putLedgerEntryLinesCategories
  def test_categorize_sends_the_bare_array
    categories = [{ id: 59, weight: "0.5" }, { id: 33, weight: "0.5" }]
    stub_request(:put, "#{API}/ledger_entry_lines/91/categories").with(body: JSON.generate(categories))
                                                                 .to_return(status: 200,
                                                                            body: '{"ledger_entry_line":{"id":91}}')

    assert_equal({ ledger_entry_line: { id: 91 } }, lines.categorize(91, categories))
  end

  def test_categorize_with_no_categories_clears_them
    stub_request(:put, "#{API}/ledger_entry_lines/91/categories").with(body: "[]")
                                                                 .to_return(status: 200,
                                                                            body: '{"ledger_entry_line":{"id":91}}')

    assert_equal({ ledger_entry_line: { id: 91 } }, lines.categorize(91, []))
  end
end
