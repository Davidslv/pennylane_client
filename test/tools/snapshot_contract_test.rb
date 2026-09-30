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
