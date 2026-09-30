# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Commercial documents, the proformas, shipping orders and purchasing
    # orders: `client.commercial_documents`.
    #
    # Attributes go to Pennylane as given, through the Encoder. Responses
    # are deep-frozen Hashes.
    class CommercialDocuments < Resource
      # Every commercial document, as an Enumerator::Lazy of Hashes. Follows
      # `next_cursor` as far as you read and sends `filter` and `sort` again
      # on every page.
      #
      #   documents.list(filter: [{ field: "document_type", operator: "eq", value: "proforma" }])
      def list(**params) = paginate(:listCommercialDocuments, **params)

      # One commercial document.
      def find(id) = call(:getCommercialDocument, id:)

      # Creates a commercial document. Pennylane requires `document_type:`
      # ("proforma", "shipping_order" or "purchasing_order"), `customer_id:`,
      # `date:`, `deadline:` and `invoice_lines:`. Its number comes from the
      # numbering for that type (`client.numberings`); without one, Pennylane
      # rejects the document.
      def create(**attributes) = call(:postCommercialDocuments, **attributes)

      # Updates a commercial document. Only the attributes you pass change;
      # the type and number never do. `invoice_lines:` and
      # `invoice_line_sections:` are `{ create: [...], update: [...],
      # delete: [...] }`, not plain Arrays.
      def update(id, **attributes) = call(:updateCommercialDocument, id:, **attributes)

      # The lists below hang off one document. Each returns every item as an
      # Enumerator::Lazy of Hashes, like `list`, and takes a smaller
      # `limit:`.

      # The document's lines. Takes `sort:`.
      def invoice_lines(commercial_document_id, **params)
        paginate(:getCommercialDocumentInvoiceLines, commercial_document_id:, **params)
      end

      # The sections that group the document's lines. Takes `sort:`.
      def invoice_line_sections(commercial_document_id, **params)
        paginate(:getCommercialDocumentInvoiceLineSections, commercial_document_id:, **params)
      end

      # Files attached to the document as appendices (not in the DMS). No
      # `sort:`.
      def appendices(commercial_document_id, **params)
        paginate(:getCommercialDocumentAppendices, commercial_document_id:, **params)
      end

      # Attaches `file` (a PDF or image: File, IO, Pathname or
      # PennylaneClient::Upload) as an appendix. It streams from disk.
      def upload_appendix(commercial_document_id, file)
        call(:postCommercialDocumentAppendices, commercial_document_id:, file:)
      end
    end
  end
end
