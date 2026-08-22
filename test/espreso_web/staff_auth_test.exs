defmodule EspresoWeb.StaffAuthTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Barista",
        email: "barista@test.local",
        password: "password123",
        role: "barista"
      })

    %{owner: owner, barista: barista}
  end

  test "orders requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/orders")
  end

  test "barista can open orders after login", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    {:ok, view, _html} = live(conn, ~p"/orders")
    assert has_element?(view, ".staff-orders-title", "Orders")
    assert has_element?(view, ".staff-orders-user", "Barista")
    refute has_element?(view, "a[href='/admin/users']", "Staff")
  end

  test "owner sees staff link and can open admin", %{conn: conn, owner: owner} do
    conn = log_in(conn, owner)
    {:ok, view, _html} = live(conn, ~p"/orders")
    assert has_element?(view, "a[href='/admin/users']", "Staff")

    {:ok, admin, _html} = live(conn, ~p"/admin/users")
    assert has_element?(admin, ".staff-orders-title", "Staff users")
  end

  test "barista cannot open admin users", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    assert {:error, {:redirect, %{to: "/orders"}}} = live(conn, ~p"/admin/users")
  end

  test "login form posts session", %{conn: conn, barista: barista} do
    {:ok, _view, html} = live(conn, ~p"/login")
    assert html =~ "Staff login"

    conn =
      post(conn, ~p"/session", %{
        "user" => %{"email" => barista.email, "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/orders"
    assert get_session(conn, :user_id) == barista.id
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end
