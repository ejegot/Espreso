defmodule EspresoWeb.Plugs.ApiAuth do
  @moduledoc """
  Bearer JWT authentication for `/api/v1` routes.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Espreso.Accounts.Token

  def init(opts), do: opts

  def call(conn, _opts) do
    case bearer_token(conn) do
      nil ->
        unauthorized(conn)

      token ->
        case Token.verify_access(token) do
          {:ok, user} ->
            assign(conn, :current_user, user)

          {:error, _} ->
            unauthorized(conn)
        end
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> String.trim(token)
      _ -> nil
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized"})
    |> halt()
  end
end
