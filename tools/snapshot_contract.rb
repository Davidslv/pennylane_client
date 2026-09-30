# frozen_string_literal: true

# Snapshot the Pennylane Company API v2 contract as published.
#
# Why: every claim the gem makes about completeness is measured against a
# dated, committed, machine-generated copy of the API, not against memory.
# The documented surface (llms.txt, then each reference page's embedded
# OpenAPI fragment) is the primary source. The full accounting.json spec is
# a cross-check only, because the docs do not link to it and it may vanish.
#
# Standard library only. Run it with `bundle exec rake contract:snapshot`.

require "json"

module SnapshotContract
  class Error < StandardError; end

  # Reads the reference page links out of llms.txt.
  module Index
    REFERENCE_LINK = %r{\((https://pennylane\.readme\.io/reference/[^)\s]+\.md)\)}

    def self.reference_urls(text)
      text.scan(REFERENCE_LINK).flatten.uniq
    end
  end

  # Pulls the OpenAPI fragment out of a reference page. Most pages fence it
  # with three backticks; pages whose description holds a code sample use
  # four, so the closing fence must match the opening one exactly.
  module Fragment
    HEADING = /^# OpenAPI definition[ \t]*$/
    OPENING = /^(`{3,})json[ \t]*\n/

    def self.extract(markdown, source_url:)
      JSON.parse(fenced_body(markdown, source_url))
    rescue JSON::ParserError => e
      raise Error, "#{source_url}: invalid OpenAPI JSON (#{e.message.lines.first.strip})"
    end

    def self.fenced_body(markdown, source_url)
      start = markdown.index(HEADING) or raise Error, "#{source_url}: no \"# OpenAPI definition\" heading"
      opening = OPENING.match(markdown, start) or raise Error, "#{source_url}: no ```json fence after the heading"
      fence = opening[1]
      finish = markdown.index(/^#{fence}[ \t]*$/, opening.end(0)) or
        raise Error, "#{source_url}: unclosed #{fence} fence"
      markdown[opening.end(0)...finish]
    end
    private_class_method :fenced_body
  end

  # Turns an OpenAPI document into one flat record per operation. Top-level
  # fields keep a fixed order for reading; every nested Hash has its keys
  # sorted, so Pennylane reordering a schema never shows up as drift.
  module Normaliser
    HTTP_METHODS = %w[get put post delete patch head options trace].freeze

    def self.operations(spec, source_url:)
      spec.fetch("paths").flat_map do |path, item|
        shared = item.fetch("parameters", [])
        item.slice(*HTTP_METHODS).map do |verb, operation|
          identity(verb, path, operation)
            .merge(schemas(operation, shared))
            .merge("source_url" => source_url)
        end
      end
    end

    def self.identity(verb, path, operation)
      {
        "operation_id" => operation.fetch("operationId"),
        "method" => verb.upcase,
        "path" => path,
        "summary" => operation["summary"],
        "description" => operation["description"],
        "tags" => operation.fetch("tags", []),
        "scopes" => scopes(operation),
        "deprecated" => operation.fetch("deprecated", false)
      }
    end

    def self.schemas(operation, shared)
      {
        "parameters" => sorted(shared + operation.fetch("parameters", [])),
        "request_body" => sorted(operation["requestBody"]),
        "responses" => sorted(operation.fetch("responses", {}))
      }
    end

    def self.scopes(operation)
      operation.fetch("security", []).flat_map { |requirement| requirement.fetch("oauth2", []) }.uniq.sort
    end

    def self.sorted(value)
      case value
      when Hash then value.sort.to_h { |key, child| [key, sorted(child)] }
      when Array then value.map { |child| sorted(child) }
      else value
      end
    end
    private_class_method :identity, :schemas, :scopes, :sorted
  end
end
