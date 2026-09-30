# frozen_string_literal: true

require "test_helper"
require "support/signatures"

# Checks that sig/ matches the code, which `rbs validate` does not:
#
# - every method defined in lib/ has a signature;
# - a public method's signature takes the same parameters as the code
#   (Method#parameters against the RBS method type);
# - every instance variable lib/ assigns is declared.
class SignaturesTest < Minitest::Test
  def test_every_method_in_lib_has_a_signature
    missing = Signatures.methods_in_lib.reject { _1.definition.methods.key?(_1.ruby.name) }

    assert_empty missing.map(&:label), "methods with no signature in sig/"
  end

  def test_public_signatures_take_the_same_parameters_as_the_code
    drifted = Signatures.methods_in_lib.filter_map { Signatures.drift(_1) }

    assert_empty drifted, "signatures whose parameters differ from the code"
  end

  # PennylaneClient.new(...) forwards to Client.new, so its signature must
  # take what Client#initialize takes.
  def test_the_forwarding_new_takes_what_client_initialize_takes
    rbs = Signatures.definition("PennylaneClient", singleton: true).methods.fetch(:new)

    assert Signatures.matches?(PennylaneClient::Client.instance_method(:initialize).parameters, rbs),
           rbs.method_types.join(" | ")
  end

  def test_every_instance_variable_assigned_in_lib_is_declared
    undeclared = Signatures.assigned_instance_variables.uniq.filter_map do |owner, singleton, ivar|
      next if Signatures.definition(owner, singleton:).instance_variables.key?(ivar)

      "#{owner}#{"." if singleton} #{ivar}"
    end

    assert_empty undeclared, "instance variables not declared in sig/"
  end
end
