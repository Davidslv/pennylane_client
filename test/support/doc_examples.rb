# frozen_string_literal: true

# Reads the Ruby examples out of a Markdown file and gives each a scope to
# run in (test/docs_examples_test.rb).
#
# A block tagged `<!-- example -->` runs. Words after `example`:
#
# - `continued`: run in the same scope as the example above it, so its
#   local variables carry over (getting started is one story);
# - a setup name (DocSetups): extra stubs, or stand-ins for Rails and
#   Sidekiq, and a check run after the example.
#
# A Ruby block that is not an example says why with `<!-- not run: ... -->`.
module DocExamples
  ROOT = File.expand_path("../..", __dir__)
  FENCE = /^```ruby\n(.*?)^```$/m
  MARKER = /<!-- (example[^>]*|not run: [^>]+) -->\n\z/
  RESULT = /\A(?<indent>\s*)(?<expression>\S.*?)\s+# => (?<result>.+)\z/

  # One tagged block: where it is, what it says, and its tag words.
  Example = Struct.new(:file, :line, :code, :words) do
    def continued? = words.include?("continued")
    def setup = (words - ["continued"]).first
    def label = "#{file}:#{line}"

    # The code, with each `expression   # => value` line whose value is a
    # Ruby literal turned into a check of that value, line for line.
    def checked_code
      code.lines.each_with_index.map do |text, index|
        match = RESULT.match(text.chomp)
        value = match && DocExamples.literal(match[:result])
        next text unless value

        "#{match[:indent]}expect_result((#{match[:expression]}), #{value}, #{line + index})\n"
      end.join
    end
  end

  # The scope an example runs in: a fresh Module, so the classes an example
  # defines stay out of the test's namespace, with `client`, WebMock's
  # `stub_request` and the stand-ins it needs. Locals persist in its
  # binding, for `continued`.
  class Sandbox < Module
    include WebMock::API

    attr_reader :client

    def initialize(client)
      super()
      @client = client
      @scope = module_eval("binding", __FILE__, __LINE__)
    end

    def let(name, value) = @scope.local_variable_set(name, value)

    def run(example) = @scope.eval(example.checked_code, File.join(ROOT, example.file), example.line)

    def expect_result(actual, expected, line)
      return if actual == expected

      raise Minitest::Assertion, "line #{line} says # => #{expected.inspect}, but it is #{actual.inspect}"
    end
  end

  # A limiter that never waits: the README's tour of the resource groups
  # alone sends more than 25 requests.
  class Unlimited
    def acquire = 0.0
    def update(remaining:, reset_at:); end
  end

  module_function

  # [code, line of its first line, text before the fence] per Ruby block.
  def blocks(file)
    text = File.read(File.join(ROOT, file))
    text.to_enum(:scan, FENCE).map do
      match = Regexp.last_match
      [match[1], text[0, match.begin(1)].count("\n") + 1, text[0, match.begin(0)]]
    end
  end

  def unmarked(file)
    blocks(file).reject { |_code, _line, before| before.match?(MARKER) }.map { |_code, line| "#{file}:#{line}" }
  end

  def examples(file)
    blocks(file).filter_map do |code, line, before|
      tag = before[MARKER, 1]
      Example.new(file, line, code, tag.split.drop(1)) if tag&.start_with?("example")
    end
  end

  # "file:line -> target#anchor" for each link to a heading that the target
  # Markdown file does not have.
  def broken_anchors(file)
    path = File.join(ROOT, file)
    File.read(path).scan(/\]\(([^)\s]*?)#([\w-]+)\)/).filter_map do |target, anchor|
      heading_file = target.empty? ? path : File.expand_path(target, File.dirname(path))
      next if anchors(heading_file).include?(anchor)

      "#{file} -> #{target}##{anchor}"
    end
  end

  # GitHub's anchor for each heading outside a code block.
  def anchors(markdown)
    text = File.read(markdown).gsub(/^```.*?^```$/m, "")
    text.scan(/^#+ (.+)$/).flatten.map { _1.downcase.gsub(/[^\w\- ]/, "").tr(" ", "-") }
  end

  # "987654, the delivery id" reads as 987654. nil for anything that is not
  # a literal.
  def literal(text)
    [text, text.split(", ").first].find do |candidate|
      Object.new.instance_eval(candidate)
      true
    rescue ScriptError, StandardError
      false
    end
  end
end
