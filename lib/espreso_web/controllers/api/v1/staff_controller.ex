defmodule EspresoWeb.Api.V1.StaffController do
  use EspresoWeb, :controller

  alias Espreso.Accounts
  alias EspresoWeb.Api.JSON

  def roster(conn, _params) do
    roster =
      Accounts.list_active_staff_for_roster()
      |> Enum.map(&JSON.roster_entry/1)

    json(conn, %{staff: roster})
  end
end
