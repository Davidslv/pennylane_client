# frozen_string_literal: true

module PennylaneClient
  module Resources
    # File attachments: `client.file_attachments`.
    #
    # An uploaded file gets an id that other calls take as
    # `file_attachment_id:`, e.g. `supplier_invoices.import` or
    # `ledger_entries.create`. It does not go into the DMS. This replaces the
    # deprecated `postLedgerAttachments`, which has no named method.
    class FileAttachments < Resource
      # Uploads `file` (a PDF or PNG, JPEG, TIFF, BMP or GIF image: File, IO,
      # Pathname or PennylaneClient::Upload, up to 100 MB). It streams from
      # disk. `filename:` overrides the name Pennylane stores.
      #
      #   file_attachments.upload(Pathname("receipt.pdf"))[:id]
      def upload(file, **fields) = call(:postFileAttachments, file:, **fields)
    end
  end
end
