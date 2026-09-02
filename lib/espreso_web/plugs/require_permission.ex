defmodule EspresoWeb.Plugs.RequirePermission do
  @moduledoc """
  Ensures the authenticated API user has a given permission.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Espreso.Accounts.Authorization

  def init(permission) when is_atom(permission), do: permission

  def call(conn, permission) do
    user = conn.assigns[:current_user]

    if Authorization.can?(user, permission) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "forbidden"})
      |> halt()
    end
  end
end
