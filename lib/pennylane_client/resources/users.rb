# frozen_string_literal: true

module PennylaneClient
  module Resources
    # Users: `client.users`, the user and company behind the token.
    class Users < Resource
      # The token's user, company and scopes, as a Hash with `:user`,
      # `:company` and `:scopes`. `:user` can be nil; the contract does
      # not say when. `:scopes` lists what the token may do.
      def me = call(:getMe)
    end
  end
end
