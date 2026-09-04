defmodule EspresoWeb.StaffShiftCloseLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Orders
  alias Espreso.Shifts

  setup %{conn: conn} do
    {:ok, manager} =
      Accounts.register_user(%{
        name: "Ana",
        email: "ana-close-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, manager.id)

    %{conn: conn, manager: manager}
  end

  test "manager can record shift close from /staff/close", %{conn: conn, manager: manager} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("140")}],
        %{customer_name: "Guest", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(order, paid_via: "gcash")

    {:ok, view, _html} = live(conn, ~p"/staff/close")

    assert has_element?(view, "#staff-shift-close-breakdown", "GCash")
    assert has_element?(view, "#staff-shift-close-breakdown", "₱140")
    assert has_element?(view, "#staff-shift-close-submit", "Record close")

    view
    |> form("#staff-shift-close-form", %{close: %{counted_cash: "140", notes: "Balanced"}})
    |> render_submit()

    assert has_element?(view, "#staff-shift-close-done", "Closed")
    assert has_element?(view, "#staff-shift-close-done", "Ana")
    assert has_element?(view, "#staff-shift-close-done", "₱140")
    refute has_element?(view, "#staff-shift-close-submit")

    close = Shifts.get_todays_close()
    assert close.closed_by_user_id == manager.id
    assert close.notes == "Balanced"
  end

  test "barista cannot open close shift", %{conn: conn} do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Mia",
        email: "mia-close-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    barista_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, barista.id)

    assert {:error, {:redirect, %{to: "/orders"}}} = live(barista_conn, ~p"/staff/close")
  end
end
