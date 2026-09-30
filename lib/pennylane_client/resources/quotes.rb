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
      def create(retry: nil, **attributes) = call(:postQuotes, retry:, **attributes)

      # Updates a quote. Only the attributes you pass change. `invoice_lines:`
      # is `{ create: [...], update: [...], delete: [...] }`, not a plain Array.
      def update(id, retry: nil, **attributes) = call_on(:updateQuote, { id: }, retry:, **attributes)

      # Emails the quote. With no `recipients:`, Pennylane uses the
      # customer's addresses. Raises ConflictError while the PDF is still
      # being generated; try again in a few minutes. Returns true.
      def send_by_email(id, retry: nil, **fields) = call_on(:sendByEmailQuote, { id: }, retry:, **fields)

      # Sets the quote's status: "pending", "accepted", "denied", "invoiced"
      # or "expired".
      #
      #   quotes.update_status(9, status: "accepted")
      def update_status(id, status:, retry: nil) = call(:updateStatusQuote, id:, status:, retry:)

      # The lists below hang off one quote. Each returns every item as an
      # Enumerator::Lazy of Hashes, like `list`, and takes a smaller
      # `limit:`.

      # The quote's lines. Takes `sort:`.
      def invoice_lines(quote_id, **params) = paginate_on(:getQuoteInvoiceLines, { quote_id: }, **params)

      # The sections that group the quote's lines. Takes `sort:`.
      def invoice_line_sections(quote_id, **params)
        paginate_on(:getQuoteInvoiceLineSections, { quote_id: }, **params)
      end

      # Files attached to the quote as appendices (not in the DMS). No `sort:`.
      def appendices(quote_id, **params) = paginate_on(:getQuoteAppendices, { quote_id: }, **params)

      # Attaches `file` (a PDF or image: File, IO, Pathname or
      # PennylaneClient::Upload) as an appendix. It streams from disk. An IO
      # with no path, such as a StringIO, goes as "upload" with
      # application/octet-stream; wrap it in Upload to name it:
      #
      #   quotes.upload_appendix(42, PennylaneClient::Upload.new(io, filename: "terms.pdf"))
      def upload_appendix(quote_id, file, retry: nil) = call(:postQuoteAppendices, quote_id:, file:, retry:)
    end
  end
end
