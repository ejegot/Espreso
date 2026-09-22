defmodule EspresoWeb.StaffHomeMoneyTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Orders
  alias Espreso.Shifts

  test "manager home shows paid breakdown; barista desk has Orders without close or money mix",
       %{
         conn: conn
       } do
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
    assert has_element?(manager_view, ".staff-home-desk-stage--split")
    assert has_element?(manager_view, "#staff-home-paid-breakdown", "Cash")
    assert has_element?(manager_view, "#staff-home-paid-breakdown", "₱75")
    assert has_element?(manager_view, "#staff-home-drawer", "Opening")
    assert has_element?(manager_view, "#staff-home-drawer", "₱0")
    assert has_element?(manager_view, "#staff-home-drawer", "Cash sales")
    assert has_element?(manager_view, "#staff-home-drawer", "₱75")
    assert has_element?(manager_view, "#staff-home-drawer", "Cash outs")
    assert has_element?(manager_view, "#staff-home-drawer", "Expected")
    refute has_element?(manager_view, "#staff-home-drawer-variance")
    assert has_element?(manager_view, "#staff-home-drawer-close", "Close shift")
    refute has_element?(manager_view, "#staff-home-shop-open")
    refute has_element?(manager_view, "#staff-home-close")
    refute has_element?(manager_view, "#staff-home-today-barista")

    barista_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, barista.id)

    {:ok, barista_view, _html} = live(barista_conn, ~p"/staff")
    refute has_element?(barista_view, "#staff-home-paid-breakdown")
    refute has_element?(barista_view, "#staff-home-drawer")
    refute has_element?(barista_view, "#staff-home-close")
    refute has_element?(barista_view, "#staff-home-today")
    refute has_element?(barista_view, ".staff-home-desk-stage--split")
    assert has_element?(barista_view, ".staff-home-desk--counter")
    assert has_element?(barista_view, "#staff-home-pos", "Open POS")
    assert has_element?(barista_view, "#staff-home-orders", "Orders")
    assert has_element?(barista_view, "#staff-home-unpaid", "Unpaid")
    assert has_element?(barista_view, "#staff-home-my-shifts", "My shifts")

    assert {:ok, _} = Shifts.record_close(manager, %{counted_cash: "75"})

    {:ok, closed_view, _html} = live(manager_conn, ~p"/staff")
    assert has_element?(closed_view, "#staff-home-shift-closed", "Closed")
    assert has_element?(closed_view, "#staff-home-drawer", "Drawer · sealed")
    assert has_element?(closed_view, "#staff-home-drawer", "Counted")
    assert has_element?(closed_view, "#staff-home-drawer-variance", "Even")
    assert has_element?(closed_view, "#staff-home-drawer-close", "View close")
    refute has_element?(closed_view, "#staff-home-shop-open")
    refute has_element?(closed_view, "#staff-home-close")
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
    assert has_element?(view, "#dashboard-paid-breakdown", "Payment methods")
    assert has_element?(view, "#dashboard-paid-breakdown", "Maya")
    assert has_element?(view, "#dashboard-paid-breakdown", "₱95")
    refute has_element?(view, "#dashboard-paid-breakdown a", "Close shift")
    refute has_element?(view, "#dashboard-panel-transactions")
  end

  test "unpaid badge shows today's unpaid count and updates after mark_paid", %{conn: conn} do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Home Unpaid Bar",
        email: "home-unpaid-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, unpaid} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Home Unpaid",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, _paid} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}],
        %{
          customer_name: "Home Paid",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :paid,
          paid_via: "cash",
          settlement_source: "pos",
          cash_tendered: Decimal.new("100")
        }
      )

    {:ok, cancelled} =
      Orders.create_order(
        [%{name: "Americano", size: nil, quantity: 1, price: Decimal.new("90")}],
        %{
          customer_name: "Home Cancelled",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, _} = Orders.cancel_order(cancelled)

    staff_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, barista.id)

    {:ok, view, _html} = live(staff_conn, ~p"/staff")

    assert has_element?(view, "#staff-home-unpaid", "Unpaid")
    assert has_element?(view, "#staff-home-unpaid .staff-home-inline-count", "1")

    {:ok, _} = Orders.mark_paid(unpaid, paid_via: "cash")

    wait_for_home_reload(view)

    html_after = render(view)
    assert has_element?(view, "#staff-home-unpaid", "Unpaid")
    refute has_element?(view, "#staff-home-unpaid .staff-home-inline-count")
    refute html_after =~ "staff-home-inline-count"
  end

  test "unpaid badge stays empty when there are no unpaid orders", %{conn: conn} do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Home Zero Bar",
        email: "home-zero-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    staff_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, barista.id)

    {:ok, view, _html} = live(staff_conn, ~p"/staff")

    assert has_element?(view, "#staff-home-unpaid", "Unpaid")
    refute has_element?(view, "#staff-home-unpaid .staff-home-inline-count")
  end

  defp wait_for_home_reload(view) do
    ms = Application.get_env(:espreso, :staff_pubsub_reload_debounce_ms, 300)
    Process.sleep(ms + 50)
    _ = :sys.get_state(view.pid)
    :ok
  end
end
