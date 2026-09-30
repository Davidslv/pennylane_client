# frozen_string_literal: true

# Compare Pennylane's live docs with the latest committed contract snapshot.
#
# Why: Pennylane ships field and operation changes every few weeks. Nobody
# should have to look. The weekly drift workflow runs this, and any
# difference becomes one GitHub issue labelled `drift` with the exact change.
# It never commits: a new snapshot lands only in a pull request together with
# the code that matches it.
#
# Documentation text (summaries, descriptions, examples) is ignored, so a
# reworded page is not drift. A schema property that happens to be called
# `description` is a field, and is compared.
#
# Standard library only. Run it with `bundle exec rake contract:drift`.

require "digest"
require "json"
require "open3"
require "tmpdir"
require_relative "snapshot_contract"
require_relative "operation_table"

# Finds and reports the difference between two contract snapshots.
module ContractDrift
  class Error < StandardError; end

  # Snapshots the docs into a temporary folder and compares it with the
  # latest snapshot committed under <root>/docs/api/contract. Writes nothing
  # under root. `fetch` is SnapshotContract's, injected so tests stay offline.
  #
  # Docs the snapshot tool refuses (a new security scheme, a duplicated
  # operationId, the two sources disagreeing) are drift too, and reported.
  # A docs site that cannot be read is not: FetchError fails the run.
  def self.run(fetch:, root:, date:, warn: Kernel.method(:warn))
    committed = File.dirname(OperationTable.latest_snapshot(File.join(root, "docs/api/contract")))
    label = committed.delete_prefix("#{root}/")
    Dir.mktmpdir("contract-drift") do |scratch|
      fresh = SnapshotContract.run(fetch: fetch, root: scratch, date: date, warn: warn)[:dir]
      compare(committed: committed, fresh: fresh, committed_label: label)
    end
  rescue SnapshotContract::FetchError
    raise
  rescue SnapshotContract::Error => e
    Report.new(diff: Diff.new([], []), guides: [], committed: label, retrieved_on: date.iso8601, refusal: e.message)
  end

  # Compares two snapshot folders (each holding operations.json and guides/).
  def self.compare(committed:, fresh:, committed_label:)
    before = JSON.parse(File.read(File.join(committed, "operations.json")))
    after = JSON.parse(File.read(File.join(fresh, "operations.json")))
    Report.new(diff: Diff.new(before.fetch("operations"), after.fetch("operations")),
               guides: changed_guides(committed, fresh),
               committed: committed_label, retrieved_on: after.fetch("retrieved_on"))
  end

  # Guide names whose body differs, ignoring the generated header that
  # carries the retrieval date.
  def self.changed_guides(committed, fresh)
    before = guides(committed)
    after = guides(fresh)
    (before.keys | after.keys).sort.reject { before[_1] == after[_1] }
  end

  def self.guides(dir)
    Dir.glob("*", base: File.join(dir, "guides")).to_h do |name|
      [name, File.read(File.join(dir, "guides", name)).sub(/\A<!--.*?-->\n\n/m, "")]
    end
  end
  private_class_method :changed_guides, :guides

  # Keeps one open GitHub issue labelled `drift` in step with the report.
  # `cli` takes the gh CLI's arguments and returns its output; it is injected
  # so tests never reach GitHub.
  module Issue
    LABEL = "drift"
    TITLE = "Pennylane API contract drift"

    # Returns what it did, for the workflow log. With no drift it leaves any
    # open issue alone: closing it is for the pull request that applies it.
    def self.sync(report, cli:)
      body = report.to_markdown or return "No drift."

      number = cli.call("issue", "list", "--label", LABEL, "--state", "open", "--json", "number",
                        "--jq", ".[0].number").strip
      return create(body, cli) if number.empty?

      cli.call("issue", "edit", number, "--body-file", "-", stdin: body)
      "Updated drift issue ##{number}."
    end

    # The body goes on stdin: a single command-line argument is capped at
    # 128 KiB on Linux, and LIMIT counts characters, not bytes.
    def self.create(body, cli)
      cli.call("label", "create", LABEL, "--color", "d93f0b", "--force",
               "--description", "Pennylane's docs differ from the committed contract snapshot")
      cli.call("issue", "create", "--title", TITLE, "--label", LABEL, "--body-file", "-", stdin: body)
      "Opened a drift issue."
    end
    private_class_method :create
  end

  # Runs the gh CLI and returns its output; raises when it fails.
  GH = lambda do |*args, stdin: nil|
    output, status = Open3.capture2("gh", *args, stdin_data: stdin.to_s)
    raise Error, "gh #{args.first(2).join(" ")} failed (#{status.exitstatus})" unless status.success?

    output
  end

  # The drift as the body of a GitHub issue.
  class Report
    # GitHub refuses an issue body over 65,536 characters.
    LIMIT = 60_000
    CUT = "\n_The report was cut to fit an issue._ Run `bundle exec rake contract:drift` locally for the full report.\n"

    # `refusal` is the snapshot tool's error when it could not read the docs.
    def initialize(diff:, guides:, committed:, retrieved_on:, refusal: nil)
      @diff = diff
      @guides = guides
      @committed = committed
      @retrieved_on = retrieved_on
      @refusal = refusal
    end

    def empty?
      @diff.empty? && @guides.empty? && @refusal.nil?
    end

    # nil when there is no drift. `limit: nil` never cuts.
    def to_markdown(limit: LIMIT)
      return if empty?

      text = (intro + sections).map { "#{_1}\n" }.join
      limit && text.length > limit ? cut(text, limit) : text
    end

    private

    def intro
      [
        "Pennylane's published docs no longer match the committed contract snapshot.", "",
        "- Committed snapshot: `#{@committed}`", "- Docs retrieved: #{@retrieved_on}", "",
        "Apply the drift in a pull request: `bundle exec rake contract:snapshot contract:sync checklist`, " \
        "then the code that matches."
      ]
    end

    def sections
      listed = { "New operations" => @diff.added, "Removed operations" => @diff.removed,
                 "Newly deprecated operations" => @diff.deprecated }
      refused + listed.flat_map { |title, records| section(title, records.map { "- #{heading(_1)}" }) } +
        changed_operations + section("Changed guides", @guides.map { "- `#{_1}`" })
    end

    def refused
      return [] unless @refusal

      section("The snapshot tool refused the docs", ["```text", @refusal.chomp, "```", "",
                                                     "Nothing else was compared. Decide whether the docs " \
                                                     "or `tools/snapshot_contract.rb` need to change."])
    end

    def section(title, lines)
      lines.empty? ? [] : ["", "### #{title}", "", *lines]
    end

    def heading(record)
      "`#{record["operation_id"]}` #{record["method"]} #{record["path"]}"
    end

    def changed_operations
      return [] if @diff.changes.empty?

      ["", "### Changed operations"] + @diff.changes.group_by(&:first).flat_map do |id, changes|
        ["", "#### #{heading(@diff.current.fetch(id))}", "", *changes.map { change(_1) }]
      end
    end

    def change(entry)
      _id, kind, path, from, to = entry
      return "- #{kind} `#{path}`" unless kind == :changed

      "- changed `#{path}`: `#{JSON.generate(from)}` → `#{JSON.generate(to)}`"
    end

    def cut(text, limit)
      kept = text[0, limit - CUT.length]
      kept[0..kept.rindex("\n")] + CUT
    end
  end

  # The difference between two lists of snapshot operation records.
  class Diff
    TEXT = %w[summary description title example examples source_url].freeze

    # The new records by operationId.
    attr_reader :current

    def initialize(old, new)
      @before = old.to_h { [_1.fetch("operation_id"), _1] }
      @current = new.to_h { [_1.fetch("operation_id"), _1] }
      @shared = (@before.keys & @current.keys).sort
    end

    def added
      @current.values_at(*(@current.keys - @before.keys).sort)
    end

    def removed
      @before.values_at(*(@before.keys - @current.keys).sort)
    end

    def deprecated
      @shared.reject { @before[_1]["deprecated"] }.select { @current[_1]["deprecated"] }.map { @current[_1] }
    end

    # Newly deprecated operations are listed by #deprecated, not here.
    def changes
      @changes ||= @shared.flat_map { |id| Diff.changes(id, @before[id], @current[id]) }
                          .reject { |_id, _kind, path, _from, to| path == "deprecated" && to == true }
    end

    def empty?
      [added, removed, deprecated, changes].all?(&:empty?)
    end

    # [operation_id, :added | :removed | :changed, path, from, to] for every
    # difference in one operation. An added or removed subtree is one entry
    # at its root, not one per leaf.
    def self.changes(id, old, new)
      before = leaves(old)
      after = leaves(new)
      entries = roots(after.keys, before.keys).map { [:added, _1, nil, nil] } +
                roots(before.keys, after.keys).map { [:removed, _1, nil, nil] } +
                changed(before, after)
      entries.sort_by { _1[1] }.map { [id, *_1] }
    end

    def self.changed(before, after)
      (before.keys & after.keys).reject { before[_1] == after[_1] }
                                .map { [:changed, _1.join("."), before[_1], after[_1]] }
    end

    # The shallowest paths under `mine` that do not exist in `theirs`.
    def self.roots(mine, theirs)
      known = nodes(theirs).to_set
      nodes(mine).reject { known.include?(_1) }
                 .select { _1.size == 1 || known.include?(_1[0...-1]) }
                 .map { _1.join(".") }
    end

    # Every path and every prefix of a path.
    def self.nodes(paths)
      paths.flat_map { |path| (1..path.size).map { path.take(_1) } }.uniq
    end

    # Every leaf value in a record, keyed by its path as an array of keys.
    def self.leaves(record)
      {}.tap { |out| walk(record.except("operation_id"), [], out, nil) }
    end

    def self.walk(value, path, out, parent)
      case value
      when Hash then walk_hash(value, path, out, parent)
      when Array then walk_array(value, path, out)
      else out[path] = value
      end
    end

    # Text keys are skipped unless they name a schema property. A hash left
    # with nothing to compare is still a leaf, so its removal is noticed.
    def self.walk_hash(hash, path, out, parent)
      kept = parent == "properties" ? hash : hash.except(*TEXT)
      return out[path] = {} if kept.empty?

      kept.each { |key, child| walk(child, path + [key], out, key) }
    end

    # List items are keyed by what they are, never by position, so inserting
    # one does not shift the others: parameters by location and name, other
    # items (oneOf, anyOf, allOf variants) by a digest of their compared
    # content. Lists of scalars (required, enum, tags) are sets.
    def self.walk_array(array, path, out)
      if !array.empty? && array.all?(Hash)
        array.each { |item| walk(item, path + [item_key(item)], out, nil) }
      elsif array.none? { _1.is_a?(Array) || _1.is_a?(Hash) }
        out[path] = array.sort_by(&:to_s)
      else
        out[path] = array
      end
    end

    def self.item_key(item)
      return "#{item["in"]}:#{item["name"]}" if item.key?("in") && item.key?("name")

      content = {}.tap { walk(item, [], _1, nil) }
      Digest::SHA256.hexdigest(JSON.generate(content.sort))[0, 8]
    end
    private_class_method :changed, :roots, :nodes, :leaves, :walk, :walk_hash, :walk_array, :item_key
  end
end

# Locally: print the full report. In the workflow, `--open-issue` also opens
# or updates the drift issue.
if $PROGRAM_NAME == __FILE__
  http = SnapshotContract::HTTP.new
  begin
    report = ContractDrift.run(fetch: http.method(:get), root: File.expand_path("..", __dir__),
                               date: Time.now.utc.to_date)
    puts report.to_markdown(limit: nil) || "No drift."
    puts ContractDrift::Issue.sync(report, cli: ContractDrift::GH) if ARGV.include?("--open-issue")
  rescue SnapshotContract::Error, OperationTable::Error, ContractDrift::Error => e
    abort e.message
  ensure
    http.finish
  end
end
