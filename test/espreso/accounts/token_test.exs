defmodule Espreso.Accounts.TokenTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.Accounts.Token

  test "issue and verify access token" do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Token User",
        email: "token.user@coffeespot.local",
        password: "password123",
        role: "barista"
      })

    assert {:ok, tokens} = Token.issue_token_pair(user)
    assert {:ok, verified} = Token.verify_access(tokens.access_token)
    assert verified.id == user.id
  end

  test "refresh token returns new access token" do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Refresh User",
        email: "refresh.user@coffeespot.local",
        password: "password123",
        role: "manager"
      })

    {:ok, tokens} = Token.issue_token_pair(user)
    assert {:ok, %{access_token: access, user: refreshed}} = Token.refresh_access(tokens.refresh_token)
    assert refreshed.id == user.id
    assert {:ok, _} = Token.verify_access(access)
  end
end
