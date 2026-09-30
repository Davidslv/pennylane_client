# frozen_string_literal: true

module PennylaneClient
  module Resources
    # File attachments: `client.file_attachments`.
    #
    # An uploaded file gets an id that other calls take as
    # `file_attachment_id:`, e.g. `supplier_invoices.import` or
    # `ledger_entries.create` (where the contract says the field will soon
    # be deprecated). It does not go into the DMS. This replaces the
    # deprecated `postLedgerAttachments`, which has no named method.
    class FileAttachments < Resource
      # Uploads `file` (a PDF or PNG, JPEG, TIFF, BMP or GIF image: File, IO,
      # Pathname or PennylaneClient::Upload, up to 100 MB). It streams from
      # disk. `filename:` overrides the name Pennylane stores.
      #
      #   file_attachments.upload(Pathname("receipt.pdf"))[:id]
      def upload(file, retry: nil, **fields) = call(:postFileAttachments, file:, retry:, **fields)
    end
  end
end
