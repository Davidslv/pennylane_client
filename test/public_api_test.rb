# frozen_string_literal: true

require "test_helper"

# The README's Public API list says what SemVer covers (proposal 0001,
# D10). Every other constant is tagged `@api private` where it is defined.
# A new constant under PennylaneClient must be one or the other, so the
# public surface only grows on purpose.
class PublicApiTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  TAG = "@api private"

  # "Client" for each `PennylaneClient::Client` in the README's list.
  def listed
    readme = File.read(File.join(ROOT, "README.md"))
    list = readme[%r{<!-- public-api[^>]*-->(.*?)<!-- /public-api -->}m, 1]
    refute_nil list, "README.md has no <!-- public-api --> list"

    list.scan(/`PennylaneClient::(\w+)/).flatten.uniq
  end

  # True when the comment directly above the definition of
  # PennylaneClient::name carries the tag.
  def tagged_private?(name)
    file, line = Object.const_source_location("PennylaneClient::#{name}")
    above = File.readlines(file).first(line - 1).reverse.take_while { _1.strip.start_with?("#") }
    above.any? { _1.include?(TAG) }
  end

  def test_every_constant_is_public_or_tagged_private
    unsorted = PennylaneClient.constants(false).map(&:to_s).reject do |name|
      listed.include?(name) ^ tagged_private?(name)
    end

    assert_empty unsorted.sort, "constants that are in the README Public API list and tagged #{TAG}, or neither"
  end

  def test_the_readme_lists_only_constants_that_exist
    assert_empty(listed.reject { PennylaneClient.const_defined?(_1, false) })
  end

  # The part classes of a Multipart are how it streams, not something a
  # caller builds or names.
  def test_the_multipart_part_classes_are_private_constants
    %i[TextSource FileSource IOSource PathSource].each do |name|
      assert PennylaneClient::Multipart.const_defined?(name, false), name
      refute_includes PennylaneClient::Multipart.constants, name
    end
    assert_raises(NameError) { PennylaneClient::Multipart::TextSource }
    assert_raises(NameError) { PennylaneClient::Multipart::FileSource }
    assert_raises(NameError) { PennylaneClient::Multipart::IOSource }
    assert_raises(NameError) { PennylaneClient::Multipart::PathSource }
  end
end
