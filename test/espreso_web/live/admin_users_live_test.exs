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

  test "owner sees staff management hierarchy and roster", %{
    conn: conn,
    owner: owner,
    barista: barista
  } do
    {:ok, view, html} = live(log_in(conn, owner), ~p"/admin/users")

    assert has_element?(view, "#staff-team-page", "Staff management")
    assert has_element?(view, ".staff-team-eyebrow", "Team")
    assert has_element?(view, "#staff-team-summary", "Active")
    assert has_element?(view, "#staff-team-summary", "Disabled")
    assert has_element?(view, "#staff-team-roster", "Team roster")
    assert has_element?(view, "#staff-team-card-#{barista.id}", "Mia")
    assert has_element?(view, "#staff-team-card-#{barista.id}", "mia.adminusers@test.local")
    assert has_element?(view, "#staff-team-card-#{barista.id}", "Staff")
    assert has_element?(view, "#staff-team-card-#{barista.id}", "Active")
    assert has_element?(view, "#user-pin-none-#{barista.id}", "No PIN")
    assert has_element?(view, "#staff-team-add-toggle", "Add staff")
    refute has_element?(view, "#staff-team-add")
    refute html =~ "pin_hash"
    refute html =~ barista.password_hash
    refute html =~ "staff-badge--pay-"
  end

  test "owner can create staff from secondary add form", %{conn: conn, owner: owner} do
    {:ok, view, _html} = live(log_in(conn, owner), ~p"/admin/users")

    view |> element("#staff-team-add-toggle") |> render_click()
    assert has_element?(view, "#staff-team-add")
    assert has_element?(view, "#admin-user-form")

    view
    |> form("#admin-user-form", %{
      user: %{
        name: "Kai",
        email: "kai.adminusers@test.local",
        password: "password123",
        role: "manager"
      }
    })
    |> render_submit()

    assert has_element?(view, "#staff-team-note", "Staff account created.")
    assert has_element?(view, "#staff-team-roster", "Kai")
    assert has_element?(view, "#staff-team-roster", "Manager")
    refute has_element?(view, "#staff-team-add")
  end

  test "owner can edit staff profile without changing own role control", %{
    conn: conn,
    owner: owner,
    barista: barista
  } do
    {:ok, view, _html} = live(log_in(conn, owner), ~p"/admin/users")

    view
    |> element(~s(button[phx-click="edit"][phx-value-id="#{barista.id}"]))
    |> render_click()

    assert has_element?(view, "#edit-user-#{barista.id}")
    assert has_element?(view, "#edit-user-#{barista.id} select[name='user[role]']")

    view
    |> form("#edit-user-#{barista.id}", %{
      user: %{
        name: "Mia Updated",
        email: "mia.adminusers@test.local",
        password: "",
        role: "barista"
      }
    })
    |> render_submit()

    assert has_element?(view, "#staff-team-note", "Staff account updated.")
    assert has_element?(view, "#staff-team-card-#{barista.id}", "Mia Updated")

    view
    |> element(~s(button[phx-click="edit"][phx-value-id="#{owner.id}"]))
    |> render_click()

    refute has_element?(view, "#edit-user-#{owner.id} select[name='user[role]']")
    assert has_element?(view, "#edit-user-#{owner.id}")
  end

  test "owner can disable and enable staff with confirmation", %{
    conn: conn,
    owner: owner,
    barista: barista
  } do
    {:ok, view, _html} = live(log_in(conn, owner), ~p"/admin/users")

    view |> element("#disable-user-#{barista.id}") |> render_click()
    assert has_element?(view, "#staff-team-confirm-disable-#{barista.id}")

    view |> element("#confirm-disable-#{barista.id}") |> render_click()
    assert has_element?(view, "#staff-team-note", "Account disabled.")
    assert has_element?(view, "#staff-team-card-#{barista.id}", "Disabled")
    refute Accounts.get_user!(barista.id).active

    view |> element("#enable-user-#{barista.id}") |> render_click()
    assert has_element?(view, "#staff-team-note", "Account enabled.")
    assert has_element?(view, "#staff-team-card-#{barista.id}", "Active")
    assert Accounts.get_user!(barista.id).active
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

    assert has_element?(view, "#staff-team-note", "PIN set for Mia.")
    assert has_element?(view, "#user-pin-set-#{barista.id}", "PIN set")
    assert Accounts.pin_set?(Accounts.get_user!(barista.id))
    assert {:ok, _} = Accounts.verify_pin(barista.id, "4321")

    view |> element("#clear-pin-#{barista.id}") |> render_click()
    assert has_element?(view, "#staff-team-confirm-clear-pin-#{barista.id}")

    view |> element("#confirm-clear-pin-#{barista.id}") |> render_click()

    assert has_element?(view, "#staff-team-note", "PIN cleared for Mia.")
    assert has_element?(view, "#user-pin-none-#{barista.id}", "No PIN")
    refute Accounts.pin_set?(Accounts.get_user!(barista.id))
  end

  test "manager and barista cannot open staff management", %{conn: conn, barista: barista} do
    {:ok, manager} =
      Accounts.register_user(%{
        name: "Manager",
        email: "manager.adminusers@test.local",
        password: "password123",
        role: "manager"
      })

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             live(log_in(conn, manager), ~p"/admin/users")

    assert {:error, {:redirect, %{to: "/orders"}}} =
             live(log_in(conn, barista), ~p"/admin/users")
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end
