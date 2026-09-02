defmodule EspresoWeb.ApiCase do
  @moduledoc false

  alias Espreso.Accounts
  alias Espreso.Accounts.Token

  def register_staff!(name, email, role \\ "barista") do
    {:ok, user} =
      Accounts.register_user(%{
        name: name,
        email: email,
        password: "password123",
        role: role
      })

    user
  end

  def auth_header(user) do
    {:ok, tokens} = Token.issue_token_pair(user)
    {"authorization", "Bearer #{tokens.access_token}"}
  end

  def auth_conn(conn, user) do
    {key, value} = auth_header(user)
    Plug.Conn.put_req_header(conn, key, value)
  end

  def json_auth_conn(conn, user) do
    conn
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> auth_conn(user)
  end
end
