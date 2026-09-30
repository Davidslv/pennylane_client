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
  # - stops when `has_more` is false or `next_cursor` is null.
  #
  # `getPaRegistrations` answers in the same shape but takes no cursor, so
  # an Operation that is not paginated is read as one page, sent as given.
  #
  # Both `items` and `pages` start again from the first page each time they
  # are enumerated.
  class Paginator
    def initialize(executor:, operation:, params:)
      raise ArgumentError, "#{operation.id.inspect} does not return a list" unless operation.verb == :get

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
        cursor = @params[:cursor]
        loop do
          page = fetch(cursor)
          yielder << page
          cursor = page[:next_cursor]
          break unless @operation.paginated && page[:has_more] && cursor
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

    def fetch(cursor)
      page = @executor.call(@operation.id, @params.merge(cursor:))
      return page if page.is_a?(Hash) && page[:items].is_a?(Array)

      raise Error, "#{@operation.id} did not return a page of items"
    end
  end
end
