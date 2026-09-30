# frozen_string_literal: true

# Stand-ins for the Rails and Sidekiq names the Rails recipes in
# docs/how-to.md use, so those recipes run like the others. Each keeps what
# it was given, for DocSetups to check.
module DocShims
  Logged = Struct.new(:lines) do
    def info(line) = lines << line
    def warn(line) = lines << line
  end

  # Rails.logger.
  module Rails
    def self.logger = @logger ||= Logged.new([])
  end

  # ActiveSupport::Notifications.instrument.
  module ActiveSupport
    # Records each instrumented event.
    module Notifications
      def self.events = @events ||= []
      def self.instrument(name, payload) = events << [name, payload]
    end
  end

  # A Sidekiq job is a class that includes Sidekiq::Job.
  module Sidekiq
    module Job; end
  end

  # A request as a controller sees it.
  Request = Struct.new(:raw_post, :headers)

  # A controller: `request` in, `head` out.
  class ApplicationController
    attr_reader :request, :status

    def self.skip_forgery_protection; end

    def initialize(request)
      @request = request
    end

    def head(status)
      @status = status
    end
  end

  # ActiveRecord's error for a unique index.
  module ActiveRecord
    class RecordNotUnique < StandardError; end
  end

  # A table of deliveries with a unique index on delivery_id.
  class PennylaneDelivery
    def self.ids = @ids ||= []

    def self.create!(delivery_id:)
      raise ActiveRecord::RecordNotUnique, "delivery_id" if ids.include?(delivery_id)

      ids << delivery_id
    end
  end

  # The job the webhook controller enqueues.
  class PennylaneEventJob
    def self.enqueued = @enqueued ||= []
    def self.perform_later(*args) = enqueued << args
  end
end
