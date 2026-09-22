defmodule EspresoWeb.StaffShopOpenLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Shifts

  setup %{conn: conn} do
    {:ok, manager} =
      Accounts.register_user(%{
        name: "Open Mgr",
        email: "open-mgr-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, manager.id)

    %{conn: conn, manager: manager}
  end

  test "manager records opening cash once", %{conn: conn, manager: manager} do
    {:ok, view, _html} = live(conn, ~p"/staff/open")

    assert has_element?(view, "#staff-shop-open-status", "Not opened")
    assert has_element?(view, "#staff-shop-open-form")

    view
    |> form("#staff-shop-open-form", %{open: %{opening_cash: ""}})
    |> render_submit()

    assert has_element?(view, "#staff-shop-open-error", "Enter the opening cash in the drawer.")

    view
    |> form("#staff-shop-open-form", %{open: %{opening_cash: "350"}})
    |> render_submit()

    assert has_element?(view, "#staff-shop-open-status", "Opened")
    assert has_element?(view, "#staff-shop-open-done", "₱350")
    refute has_element?(view, "#staff-shop-open-form")

    open = Shifts.get_todays_open()
    assert open.opened_by_user_id == manager.id
    assert Decimal.equal?(open.opening_cash, Decimal.new("350"))
  end

  test "barista can open shop day", %{conn: conn} do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Open Bar",
        email: "open-bar-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    barista_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, barista.id)

    {:ok, view, _html} = live(barista_conn, ~p"/staff/open")
    assert has_element?(view, "#staff-shop-open-submit", "Record opening cash")
  end
end
