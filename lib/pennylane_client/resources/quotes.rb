# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Quotes: `client.quotes`.
    #
    # Attributes go to Pennylane as given, through the Encoder. Responses
    # are deep-frozen Hashes; an action Pennylane answers with no content
    # returns true.
    class Quotes < Resource
      # Every quote, as an Enumerator::Lazy of Hashes. Follows `next_cursor`
      # as far as you read and sends `filter` and `sort` again on every page.
      #
      #   quotes.list(filter: [{ field: "status", operator: "eq", value: "pending" }], sort: "-id")
      def list(**params) = paginate(:listQuotes, **params)

      # One quote.
      def find(id) = call(:getQuote, id:)

      # Creates a quote. Pennylane requires `customer_id:`, `date:`,
      # `deadline:` and `invoice_lines:`. Its number comes from the company's
      # `estimate` numbering (`client.numberings`).
      def create(**attributes) = call(:postQuotes, **attributes)

      # Updates a quote. Only the attributes you pass change. `invoice_lines:`
      # is `{ create: [...], update: [...], delete: [...] }`, not a plain Array.
      def update(id, **attributes) = call(:updateQuote, id:, **attributes)

      # Emails the quote. With no `recipients:`, Pennylane uses the
      # customer's addresses. Raises ConflictError while the PDF is still
      # being generated; try again in a few minutes. Returns true.
      def send_by_email(id, **fields) = call(:sendByEmailQuote, id:, **fields)

      # Sets the quote's status: "pending", "accepted", "denied", "invoiced"
      # or "expired".
      #
      #   quotes.update_status(9, status: "accepted")
      def update_status(id, status:) = call(:updateStatusQuote, id:, status:)

      # The lists below hang off one quote. Each returns every item as an
      # Enumerator::Lazy of Hashes, like `list`, and takes a smaller
      # `limit:`.

      # The quote's lines. Takes `sort:`.
      def invoice_lines(quote_id, **params) = paginate(:getQuoteInvoiceLines, quote_id:, **params)

      # The sections that group the quote's lines. Takes `sort:`.
      def invoice_line_sections(quote_id, **params)
        paginate(:getQuoteInvoiceLineSections, quote_id:, **params)
      end

      # Files attached to the quote as appendices (not in the DMS). No `sort:`.
      def appendices(quote_id, **params) = paginate(:getQuoteAppendices, quote_id:, **params)

      # Attaches `file` (a PDF or image: File, IO, Pathname or
      # PennylaneClient::Upload) as an appendix. It streams from disk.
      def upload_appendix(quote_id, file) = call(:postQuoteAppendices, quote_id:, file:)
    end
  end
end
