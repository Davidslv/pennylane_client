# frozen_string_literal: true

module PennylaneClient
  # Process-wide defaults, read when a Client is built.
  #
  #   PennylaneClient.configure do |config|
  #     config.logger = Rails.logger
  #     config.on_request = ->(event) { StatsD.measure("pennylane", event[:duration]) }
  #   end
  #
  # - logger: anything with #info and #warn; one line per attempt, retry
  #   and rate-limit wait.
  # - on_request: a callable given one frozen event Hash for each of those
  #   (see Instrumentation).
  #
  # A Client reads both when it is built, so configure before building one.
  class Configuration
    attr_accessor :logger, :on_request
  end
end
