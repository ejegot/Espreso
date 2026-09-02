defmodule EspresoWeb.AdminUsersLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.adminusers@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Mia",
        email: "mia.adminusers@test.local",
        password: "password123",
        role: "barista"
      })

    %{owner: owner, barista: barista}
  end

  test "owner can set and clear staff PIN", %{conn: conn, owner: owner, barista: barista} do
    refute Accounts.pin_set?(barista)

    {:ok, view, _html} = live(log_in(conn, owner), ~p"/admin/users")

    view
    |> element("button[phx-click=edit][phx-value-id=\"#{barista.id}\"]")
    |> render_click()
    assert has_element?(view, "#pin-form-#{barista.id}")

    view
    |> form("#pin-form-#{barista.id}", %{pin: "4321"})
    |> render_submit()

    assert has_element?(view, ".staff-admin-note", "PIN set for Mia.")
    assert has_element?(view, "#user-pin-set-#{barista.id}", "PIN set")
    assert Accounts.pin_set?(Accounts.get_user!(barista.id))
    assert {:ok, _} = Accounts.verify_pin(barista.id, "4321")

    view |> element("#clear-pin-#{barista.id}") |> render_click()

    assert has_element?(view, ".staff-admin-note", "PIN cleared for Mia.")
    refute Accounts.pin_set?(Accounts.get_user!(barista.id))
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end
