defmodule EspresoWeb.StaffShiftCloseLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Menu
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

  test "manager sees close hierarchy and can record shift close", %{conn: conn, manager: manager} do
    {:ok, cash_order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Cash Guest", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, gcash_order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("140")}],
        %{customer_name: "Guest", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(cash_order, paid_via: "cash")
    {:ok, _} = Orders.mark_paid(gcash_order, paid_via: "gcash")

    {:ok, view, _html} = live(conn, ~p"/staff/close")

    assert has_element?(view, "#staff-shift-close-status", "Open")
    assert has_element?(view, "#staff-shift-close-cash", "Cash settled")
    assert has_element?(view, "#staff-shift-close-cash", "₱75")
    assert has_element?(view, "#staff-shift-close-counted-field", "Counted drawer cash")
    assert has_element?(view, "#staff-shift-close-counted-hint", "Optional")
    assert has_element?(view, "#staff-shift-close-breakdown", "GCash")
    assert has_element?(view, "#staff-shift-close-breakdown", "₱140")
    assert has_element?(view, "#staff-shift-close-system", "System paid")
    assert has_element?(view, "#staff-shift-close-system", "₱215")
    assert has_element?(view, "#staff-shift-close-prepare", "Record close")
    refute has_element?(view, "#staff-shift-close-confirm")

    view
    |> form("#staff-shift-close-form", %{close: %{counted_cash: "80", notes: "Balanced"}})
    |> render_submit()

    assert has_element?(view, "#staff-shift-close-confirm", "Record today’s close?")
    assert has_element?(view, "#staff-shift-close-confirm-cash", "Counted drawer cash · ₱80")
    assert has_element?(view, "#staff-shift-close-submit", "Confirm seal")

    view
    |> element("#staff-shift-close-submit")
    |> render_click()

    assert has_element?(view, "#staff-shift-close-status", "Shift closed")
    assert has_element?(view, "#staff-shift-close-done", "Shift closed")
    assert has_element?(view, "#staff-shift-close-done-meta", "Ana")
    assert has_element?(view, "#staff-shift-close-sealed-system", "₱215")
    assert has_element?(view, "#staff-shift-close-sealed-system", "2 orders")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "Cash")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "₱75")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "GCash")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "₱140")
    assert has_element?(view, "#staff-shift-close-sealed-cash", "₱75")
    assert has_element?(view, "#staff-shift-close-sealed-counted", "₱80")
    assert has_element?(view, "#staff-shift-close-sealed-notes", "Balanced")
    assert has_element?(view, "#staff-shift-close-done a[href='/staff']", "Back to Home")
    assert has_element?(view, "#staff-shift-close-done a[href='/dashboard']", "Back to Dashboard")

    assert has_element?(
             view,
             "#staff-shift-close-done a[href='/transactions']",
             "View Transactions"
           )

    refute has_element?(view, "#staff-shift-close-prepare")
    refute has_element?(view, "#staff-shift-close-submit")

    close = Shifts.get_todays_close()
    assert close.closed_by_user_id == manager.id
    assert close.notes == "Balanced"
    assert Decimal.equal?(close.system_total, Decimal.new("215"))
    assert close.system_count == 2
    assert Decimal.equal?(close.counted_cash, Decimal.new("80"))
  end

  test "closed state shows sealed snapshot not later live totals", %{conn: conn, manager: manager} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("140")}],
        %{customer_name: "Guest", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(order, paid_via: "gcash")

    assert {:ok, _close} =
             Shifts.record_close(manager, %{
               "counted_cash" => "140",
               "notes" => "End of day"
             })

    {:ok, late} =
      Orders.create_order(
        [%{name: "Americano", size: nil, quantity: 1, price: Decimal.new("95")}],
        %{customer_name: "Late", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(late, paid_via: "cash")

    live_total = Orders.todays_paid_breakdown().total
    assert Decimal.equal?(live_total, Decimal.new("235"))

    {:ok, view, _html} = live(conn, ~p"/staff/close")

    assert has_element?(view, "#staff-shift-close-status", "Shift closed")

    assert has_element?(
             view,
             "#staff-shift-close-sealed-system",
             Menu.format_price(Decimal.new("140"))
           )

    assert has_element?(view, "#staff-shift-close-sealed-system", "1 orders")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "GCash")
    assert has_element?(view, "#staff-shift-close-sealed-breakdown", "₱140")
    assert has_element?(view, "#staff-shift-close-sealed-cash", "₱0")
    assert has_element?(view, "#staff-shift-close-sealed-counted", "₱140")
    refute has_element?(view, "#staff-shift-close-sealed-system", "₱235")
    refute has_element?(view, "#staff-shift-close-form")
  end

  test "prepare close with blank counted cash states no drawer count", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/staff/close")

    view
    |> form("#staff-shift-close-form", %{close: %{counted_cash: "", notes: ""}})
    |> render_submit()

    assert has_element?(view, "#staff-shift-close-confirm-cash", "No drawer cash count entered.")
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
