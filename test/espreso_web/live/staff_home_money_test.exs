defmodule EspresoWeb.StaffHomeMoneyTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Orders
  alias Espreso.Shifts

  test "manager home shows paid breakdown and close tile; barista does not", %{conn: conn} do
    {:ok, manager} =
      Accounts.register_user(%{
        name: "Mgr",
        email: "mgr-home-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Bar",
        email: "bar-home-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Pay", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(order, paid_via: "cash")

    manager_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, manager.id)

    {:ok, manager_view, _html} = live(manager_conn, ~p"/staff")
    assert has_element?(manager_view, "#staff-home-paid-breakdown", "Cash")
    assert has_element?(manager_view, "#staff-home-paid-breakdown", "₱75")
    assert has_element?(manager_view, "#staff-home-close", "Close shift")
    refute has_element?(manager_view, "#staff-home-today-barista")

    barista_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, barista.id)

    {:ok, barista_view, _html} = live(barista_conn, ~p"/staff")
    refute has_element?(barista_view, "#staff-home-paid-breakdown")
    refute has_element?(barista_view, "#staff-home-close")
    assert has_element?(barista_view, "#staff-home-today-barista")

    assert {:ok, _} = Shifts.record_close(manager, %{counted_cash: "75"})

    {:ok, closed_view, _html} = live(manager_conn, ~p"/staff")
    assert has_element?(closed_view, "#staff-home-shift-closed", "Closed")
    assert has_element?(closed_view, "#staff-home-close", "Shift closed")
  end

  test "dashboard shows today by payment for manager", %{conn: conn} do
    {:ok, manager} =
      Accounts.register_user(%{
        name: "Dash",
        email: "dash-home-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, order} =
      Orders.create_order(
        [%{name: "Americano", size: nil, quantity: 1, price: Decimal.new("95")}],
        %{customer_name: "Dash Guest", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(order, paid_via: "maya")

    manager_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, manager.id)

    {:ok, view, _html} = live(manager_conn, ~p"/dashboard")
    assert has_element?(view, "#dashboard-paid-breakdown", "Today by payment")
    assert has_element?(view, "#dashboard-paid-breakdown", "Maya")
    assert has_element?(view, "#dashboard-paid-breakdown", "₱95")
    assert has_element?(view, "#dashboard-paid-breakdown a", "Close shift")
  end
end
