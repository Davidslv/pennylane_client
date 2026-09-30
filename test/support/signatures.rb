# frozen_string_literal: true

require "prism"
require "rbs"

# Reads sig/ with the rbs library and lib/ by reflection and with Prism, so
# SignaturesTest can compare them. `rbs validate` only checks that the
# signatures are well formed, not that they match the code.
module Signatures
  ROOT = File.expand_path("../..", __dir__)
  LIB = File.join(ROOT, "lib")
  # `def name(...)`: takes whatever its target takes.
  FORWARDING = [%i[rest *], %i[keyrest **], %i[block &]].freeze
  IVAR_WRITES = [Prism::InstanceVariableWriteNode, Prism::InstanceVariableOrWriteNode,
                 Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableOperatorWriteNode,
                 Prism::InstanceVariableTargetNode].freeze

  # One method defined in lib/, with the RBS definition of its owner.
  Entry = Struct.new(:label, :ruby, :definition, :public)

  module_function

  def builder
    @builder ||= begin
      loader = RBS::EnvironmentLoader.new
      loader.add(library: "date")
      loader.add(path: Pathname(File.join(ROOT, "sig")))
      RBS::DefinitionBuilder.new(env: RBS::Environment.from_loader(loader).resolve_type_names)
    end
  end

  def type_name(name) = RBS::TypeName.parse("::#{name}")

  def definition(name, singleton:)
    singleton ? builder.build_singleton(type_name(name)) : builder.build_instance(type_name(name))
  end

  # Every class and module under PennylaneClient.
  def namespaces(mod = PennylaneClient, seen = [])
    return seen if seen.include?(mod)

    seen << mod
    children = mod.constants(false).map { mod.const_get(_1) }.grep(Module)
    children.select { _1.name&.start_with?("PennylaneClient") }.each { namespaces(_1, seen) }
    seen
  end

  # Every method lib/ defines, public or not, instance or singleton.
  def methods_in_lib
    namespaces.flat_map { instance_entries(_1) + singleton_entries(_1) }
  end

  def instance_entries(mod)
    names = mod.public_instance_methods(false) + mod.private_instance_methods(false) +
            mod.protected_instance_methods(false)
    entries(mod, "#", names.map { mod.instance_method(_1) }, singleton: false) do |name|
      mod.public_method_defined?(name, false)
    end
  end

  def singleton_entries(mod)
    names = (mod.singleton_methods(false) + mod.singleton_class.private_instance_methods(false)).uniq
    entries(mod, ".", names.map { mod.method(_1) }, singleton: true) do |name|
      mod.singleton_class.public_method_defined?(name)
    end
  end

  def entries(mod, separator, methods, singleton:)
    methods = methods.select { _1.source_location&.first&.start_with?(LIB) }
    return [] if methods.empty?

    definition = definition(mod.name, singleton:)
    methods.map { Entry.new("#{mod.name}#{separator}#{_1.name}", _1, definition, yield(_1.name)) }
  end

  # "label: code ..., sig ..." when a public method's signature takes other
  # parameters than the code, nil otherwise. A `(...)` method is skipped.
  def drift(entry)
    rbs = entry.definition.methods[entry.ruby.name]
    parameters = entry.ruby.parameters
    return if !entry.public || rbs.nil? || parameters == FORWARDING || matches?(parameters, rbs)

    "#{entry.label}: code #{shape(parameters)}, sig #{rbs.method_types.join(" | ")}"
  end

  # True when the Ruby parameters fit one of the RBS method types.
  def matches?(parameters, rbs_method)
    rbs_method.method_types.any? do |method_type|
      function = method_type.type
      function.is_a?(RBS::Types::UntypedFunction) || shape(parameters) == rbs_shape(function)
    end
  end

  # What the Ruby parameters look like: positional counts, rest, keyword
  # names, keyword rest. Positional names and the block are not compared.
  def shape(parameters)
    kinds = parameters.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    { req: kinds.fetch(:req, []).size, opt: kinds.fetch(:opt, []).size, rest: kinds.key?(:rest),
      keyreq: kinds.fetch(:keyreq, []).sort, key: kinds.fetch(:key, []).sort, keyrest: kinds.key?(:keyrest) }
  end

  def rbs_shape(function)
    { req: function.required_positionals.size + function.trailing_positionals.size,
      opt: function.optional_positionals.size, rest: !function.rest_positionals.nil?,
      **rbs_keywords(function) }
  end

  def rbs_keywords(function)
    { keyreq: function.required_keywords.keys.sort, key: function.optional_keywords.keys.sort,
      keyrest: !function.rest_keywords.nil? }
  end

  # [[owner name, singleton?, :@ivar], ...] for every assignment in lib/.
  def assigned_instance_variables
    Dir.glob("**/*.rb", base: LIB).sort.flat_map do |file|
      [].tap { walk(Prism.parse_file(File.join(LIB, file)).value, [], false, _1) }
    end
  end

  def walk(node, namespace, singleton, found)
    case node
    when Prism::ClassNode, Prism::ModuleNode then namespace += [node.constant_path.slice]
                                                  singleton = false
    when Prism::ConstantWriteNode then namespace += [node.name.to_s]
    when Prism::SingletonClassNode then singleton = true
    when Prism::DefNode then singleton = !node.receiver.nil?
    when *IVAR_WRITES then found << [namespace.join("::"), singleton, node.name]
    end
    node.compact_child_nodes.each { walk(_1, namespace, singleton, found) }
  end
end
