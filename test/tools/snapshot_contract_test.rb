# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tools/snapshot_contract"

module SnapshotContractFixtures
  DIR = File.expand_path("../fixtures/contract", __dir__)

  def fixture(name)
    File.read(File.join(DIR, name), encoding: "UTF-8")
  end

  def page(name)
    fixture("pages/#{name}.md")
  end

  # What the network would serve, keyed by URL. A missing key is a 404.
  def site
    pages = %w[getjournal postjournals postledgerattachments].to_h do |name|
      ["https://pennylane.readme.io/reference/#{name}.md", page(name)]
    end
    pages.merge(
      SnapshotContract::INDEX_URL => fixture("llms.txt"),
      SnapshotContract::FULL_SPEC_URL => fixture("accounting.json")
    )
  end
end

class SnapshotContractIndexTest < Minitest::Test
  include SnapshotContractFixtures

  def test_lists_every_reference_page_once_in_index_order
    urls = SnapshotContract::Index.reference_urls(fixture("llms.txt"))

    assert_equal %w[
      https://pennylane.readme.io/reference/getjournal.md
      https://pennylane.readme.io/reference/postjournals.md
      https://pennylane.readme.io/reference/postledgerattachments.md
    ], urls
  end
end

class SnapshotContractFragmentTest < Minitest::Test
  include SnapshotContractFixtures

  def test_extracts_the_fragment_from_a_three_backtick_fence
    spec = SnapshotContract::Fragment.extract(page("getjournal"), source_url: "getjournal.md")

    assert_equal ["/api/external/v2/journals/{id}"], spec.fetch("paths").keys
  end

  def test_extracts_the_fragment_from_a_four_backtick_fence_that_wraps_a_three_backtick_one
    spec = SnapshotContract::Fragment.extract(page("postjournals"), source_url: "postjournals.md")
    operation = spec.dig("paths", "/api/external/v2/journals", "post")

    assert_equal "postJournals", operation.fetch("operationId")
    assert_includes operation.fetch("description"), "```"
  end

  def test_names_the_page_when_there_is_no_openapi_definition
    error = assert_raises(SnapshotContract::Error) do
      SnapshotContract::Fragment.extract("# Retrieve a journal\n\nNo spec here.\n", source_url: "getjournal.md")
    end

    assert_match(/getjournal\.md: no "# OpenAPI definition" heading/, error.message)
  end

  def test_names_the_page_when_the_fence_is_never_closed
    markdown = "# OpenAPI definition\n\n````json\n{}\n```\n"

    error = assert_raises(SnapshotContract::Error) do
      SnapshotContract::Fragment.extract(markdown, source_url: "broken.md")
    end

    assert_match(/broken\.md: unclosed ```` fence/, error.message)
  end

  def test_names_the_page_when_the_fragment_is_not_json
    markdown = "# OpenAPI definition\n\n```json\n{ not json\n```\n"

    error = assert_raises(SnapshotContract::Error) do
      SnapshotContract::Fragment.extract(markdown, source_url: "broken.md")
    end

    assert_match(/broken\.md: invalid OpenAPI JSON/, error.message)
  end
end

class SnapshotContractNormaliserTest < Minitest::Test
  include SnapshotContractFixtures

  def normalise(name)
    url = "https://pennylane.readme.io/reference/#{name}.md"
    spec = SnapshotContract::Fragment.extract(page(name), source_url: url)
    SnapshotContract::Normaliser.operations(spec, source_url: url)
  end

  def test_keeps_the_fields_the_gem_depends_on_in_a_fixed_order
    operation = normalise("getjournal").first

    assert_equal %w[operation_id method path summary description tags scopes deprecated
                    parameters request_body responses source_url], operation.keys
    assert_equal "getJournal", operation["operation_id"]
    assert_equal "GET", operation["method"]
    assert_equal "/api/external/v2/journals/{id}", operation["path"]
    assert_equal ["Journals"], operation["tags"]
    assert_equal "https://pennylane.readme.io/reference/getjournal.md", operation["source_url"]
  end

  def test_scopes_are_every_oauth2_scope_sorted_once
    assert_equal %w[journals:all journals:readonly], normalise("getjournal").first["scopes"]
    assert_equal %w[file_attachments:all ledger], normalise("postledgerattachments").first["scopes"]
  end

  def test_deprecated_defaults_to_false
    refute normalise("getjournal").first["deprecated"]
    assert normalise("postledgerattachments").first["deprecated"]
  end

  def test_request_body_is_nil_when_the_operation_takes_none
    assert_nil normalise("getjournal").first["request_body"]
    assert_equal ["multipart/form-data"], normalise("postledgerattachments").first["request_body"]["content"].keys
  end

  def test_path_level_parameters_come_before_operation_parameters
    names = normalise("postledgerattachments").first["parameters"].map { _1["name"] }

    assert_equal ["X-Request-Source"], names
  end

  def test_schema_keys_are_sorted_so_a_reordered_page_makes_no_diff
    schema = normalise("getjournal").first.dig("responses", "200", "content", "application/json", "schema")

    assert_equal %w[properties required type], schema.keys
    assert_equal %w[id label], schema["properties"].keys
    assert_equal %w[label id], schema["required"], "arrays keep the source order"
  end
end

class SnapshotContractSnapshotTest < Minitest::Test
  include SnapshotContractFixtures

  def setup
    @warnings = []
  end

  def snapshot(served)
    SnapshotContract::Snapshot.new(fetch: served.method(:[]), warn: @warnings.method(:<<))
  end

  def test_returns_every_documented_operation_sorted_by_operation_id
    ids = snapshot(site).operations.map { _1["operation_id"] }

    assert_equal %w[getJournal postJournals postLedgerAttachments], ids
    assert_empty @warnings
  end

  def test_fails_when_llms_txt_is_missing
    served = site.except(SnapshotContract::INDEX_URL)

    error = assert_raises(SnapshotContract::Error) { snapshot(served).operations }

    assert_equal "GET #{SnapshotContract::INDEX_URL}: not found", error.message
  end

  def test_fails_when_a_listed_reference_page_is_missing
    served = site.except("https://pennylane.readme.io/reference/postjournals.md")

    error = assert_raises(SnapshotContract::Error) { snapshot(served).operations }

    assert_match(/postjournals\.md: not found/, error.message)
  end

  def test_fails_when_two_pages_document_the_same_operation_id
    served = site.merge("https://pennylane.readme.io/reference/postjournals.md" => page("getjournal"))

    error = assert_raises(SnapshotContract::Error) { snapshot(served).operations }

    assert_match(/getJournal is documented more than once/, error.message)
  end

  # accounting.json without postJournals and with an extra deleteJournal.
  def disagreeing_full_spec
    full = JSON.parse(fixture("accounting.json"))
    full["paths"].delete("/api/external/v2/journals")
    full["paths"]["/api/external/v2/journals/{id}"]["delete"] = { "operationId" => "deleteJournal" }
    JSON.generate(full)
  end

  def test_fails_with_a_readable_diff_when_accounting_json_disagrees
    served = site.merge(SnapshotContract::FULL_SPEC_URL => disagreeing_full_spec)

    error = assert_raises(SnapshotContract::Error) { snapshot(served).operations }

    assert_equal <<~DIFF, error.message
      The reference pages and accounting.json list different operations.
        only in the reference pages:
          + postJournals POST /api/external/v2/journals
        only in accounting.json:
          - deleteJournal DELETE /api/external/v2/journals/{id}
    DIFF
  end

  def test_warns_and_carries_on_when_accounting_json_is_gone
    served = site.except(SnapshotContract::FULL_SPEC_URL)

    assert_equal 3, snapshot(served).operations.size
    assert_equal ["#{SnapshotContract::FULL_SPEC_URL} is gone; skipping the cross-check"], @warnings
  end
end
