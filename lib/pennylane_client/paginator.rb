# frozen_string_literal: true

module PennylaneClient
  # Walks a cursor-paginated list, one request per page, only as far as the
  # caller reads (docs/api/contract/<date>/guides/cursor-pagination.md):
  #
  # - asks for the largest page the Operation allows (100 or 1000), unless
  #   the caller passed a smaller `limit`, so a long list costs as few calls
  #   from the rate limit as it can;
  # - sends every param again on every page, next to the `cursor`, because
  #   the cursor does not remember `filter` or `sort`;
  # - except `start_date`, which goes with the first request only: every
  #   changelog operation answers 400 to `start_date` next to a `cursor`,
  #   which is also why the caller cannot pass both;
  # - stops when `has_more` is false or `next_cursor` is null.
  #
  # `getPaRegistrations` answers in the same shape but takes no cursor, so
  # an Operation that is not paginated is read as one page, sent as given.
  # If that page says `has_more: true`, the rest cannot be asked for, so the
  # walk raises Error rather than return part of the list.
  #
  # Both `items` and `pages` start again from the first page each time they
  # are enumerated.
  class Paginator
    FIRST_PAGE_ONLY = %i[start_date].freeze

    def initialize(executor:, operation:, params:)
      raise ArgumentError, "#{operation.id.inspect} does not return a list" unless operation.verb == :get
      raise ArgumentError, "pass start_date or cursor, not both" if params[:start_date] && params[:cursor]

      @executor = executor
      @operation = operation
      @params = operation.paginated ? with_limit(params) : params
    end

    # Every item of every page, as an Enumerator::Lazy of Hashes.
    def items = pages.flat_map { _1.fetch(:items) }

    # Every page, as an Enumerator::Lazy of Hashes with `items`, `has_more`
    # and `next_cursor`.
    def pages
      Enumerator.new do |yielder|
        params = @params
        loop do
          page = fetch(params)
          yielder << page
          break unless more?(page)

          params = @params.except(*FIRST_PAGE_ONLY).merge(cursor: next_cursor(page, params[:cursor]))
        end
      end.lazy
    end

    def inspect = "#<#{self.class.name} operation_id=#{@operation.id.inspect}>"

    private

    def with_limit(params)
      max = @operation.max_limit
      limit = params.fetch(:limit, max)
      unless limit.is_a?(Integer) && limit.between?(1, max)
        raise ArgumentError, "limit for #{@operation.id.inspect} must be 1 to #{max}, got #{limit.inspect}"
      end

      params.merge(limit:)
    end

    # True when there is a next page to ask for. An Operation that takes no
    # cursor cannot ask for one, so `has_more: true` from it raises.
    def more?(page)
      return false unless page[:has_more]
      raise Error, "#{@operation.id} answered has_more: true, but takes no cursor" unless @operation.paginated

      !page[:next_cursor].nil?
    end

    # The same cursor twice would ask for the same page forever.
    def next_cursor(page, cursor)
      return page[:next_cursor] unless page[:next_cursor] == cursor

      raise Error, "#{@operation.id} returned the cursor it was given, #{cursor.inspect}"
    end

    def fetch(params)
      page = @executor.call(@operation.id, params)
      return page if page.is_a?(Hash) && page[:items].is_a?(Array)

      raise Error, "#{@operation.id} did not return a page of items"
    end
  end
end
