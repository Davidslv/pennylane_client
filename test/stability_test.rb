# frozen_string_literal: true

require "test_helper"

# The README's Experimental list and the `@note Experimental` markers in
# lib/ name the same methods, so neither can drift from the other. An
# Experimental method sits outside the SemVer promise (proposal 0001, D9),
# so a caller must be able to trust the list.
class StabilityTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  MARKER = "@note Experimental:"

  def client = @client ||= PennylaneClient.new(token: "tok", limiters: PennylaneClient::LimiterRegistry.new)

  # "Customers#create" for each `client.customers.create` in the README's
  # Experimental list.
  def listed
    readme = File.read(File.join(ROOT, "README.md"))
    list = readme[%r{<!-- experimental[^>]*-->(.*?)<!-- /experimental -->}m, 1]
    refute_nil list, "README.md has no <!-- experimental --> list"

    list.scan(/`client\.(\w+)\.(\w+)`/).map do |accessor, name|
      "#{client.public_send(accessor).class.name.split("::").last}##{name}"
    end
  end

  # "Customers#create" for each method whose comment carries the marker.
  def marked
    Dir.glob(File.join(ROOT, "lib/pennylane_client/resources/*.rb")).flat_map do |file|
      marked_in(File.readlines(file))
    end
  end

  def marked_in(lines)
    klass = nil
    comment = []
    lines.each_with_object([]) do |line, found|
      klass = Regexp.last_match(1) if line =~ /^\s*class (\w+)/
      found << "#{klass}##{Regexp.last_match(1)}" if line =~ /^\s*def (\w+)/ && comment.any? { _1.include?(MARKER) }
      comment = line.strip.start_with?("#") ? comment + [line] : []
    end
  end

  def test_the_readme_lists_exactly_the_methods_marked_experimental
    refute_empty marked

    assert_equal marked.sort, listed.sort
  end

  def test_every_experimental_method_exists
    listed.each do |label|
      klass, name = label.split("#")

      assert PennylaneClient::Resources.const_get(klass).public_method_defined?(name, false), label
    end
  end

  def test_the_readme_says_experimental_is_outside_semver
    readme = File.read(File.join(ROOT, "README.md"))

    assert_match(/^## Stability$/, readme)
    assert_includes readme, "Experimental APIs may change in a minor release"
  end
end
