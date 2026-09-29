defmodule EspresoWeb.BranchSessionController do
  @moduledoc false
  use EspresoWeb, :controller

  alias Espreso.Tenancy

  def update(conn, %{"branch_id" => branch_id}) do
    user = conn.assigns.current_user
    working = Tenancy.resolve_working_branch_id(user, branch_id)

    conn
    |> put_session(:branch_id, working)
    |> redirect(to: redirect_path(conn))
  end

  def update(conn, _params) do
    redirect(conn, to: ~p"/staff")
  end

  defp redirect_path(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] ->
        uri = URI.parse(referer)

        if is_binary(uri.path) and String.starts_with?(uri.path, "/"),
          do: uri.path,
          else: ~p"/staff"

      _ ->
        ~p"/staff"
    end
  end
end
