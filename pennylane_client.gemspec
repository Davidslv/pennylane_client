# frozen_string_literal: true

require_relative "lib/pennylane_client/version"

Gem::Specification.new do |spec|
  spec.name = "pennylane_client"
  spec.version = PennylaneClient::VERSION
  spec.authors = ["David Silva"]
  spec.email = ["davidslv@users.noreply.github.com"]

  spec.summary = "Unofficial Ruby client for the Pennylane Company API v2. Not affiliated with Pennylane."
  spec.description = "A zero-dependency Ruby client for the Pennylane Company API v2: every operation " \
                     "reachable, stable Ruby names, client-side rate limiting, safe retries and cursor " \
                     "pagination. Built from Pennylane's public documentation. Not affiliated with Pennylane."
  spec.homepage = "https://github.com/Davidslv/pennylane_client"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship library code, signatures and the legal files only. Everything else
  # (tests, tools, docs, the contract snapshot, proposals) stays in the repo.
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |f|
      f.start_with?("lib/", "sig/") || %w[README.md LICENSE.txt CHANGELOG.md].include?(f)
    end
  end
  spec.require_paths = ["lib"]
end
