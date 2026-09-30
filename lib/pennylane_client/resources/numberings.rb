# frozen_string_literal: true

module PennylaneClient
  module Resources
    # The company's document numberings: `client.numberings`. Read only.
    class Numberings < Resource
      # Every numbering, one per configured document type, as an
      # Enumerator::Lazy of Hashes. Takes `sort:`. A type with no numbering is
      # absent, and Pennylane then refuses the documents that need it:
      # `invoice` to finalize a customer invoice, `estimate` to number a
      # quote, `proforma`, `shipping_order` and `purchasing_order` to create
      # that commercial document.
      #
      #   client.numberings.list.any? { _1[:document_type] == "proforma" }
      def list(**params) = paginate(:getNumberings, **params)
    end
  end
end
