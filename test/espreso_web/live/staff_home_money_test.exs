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
    assert has_element?(manager_view, "#staff-home-kpis")
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
    assert has_element?(manager_view, "#staff-home-pos", "Open POS")
    assert has_element?(manager_view, "#dashboard-panel-sales", "Total Sales Today")
    assert has_element?(manager_view, "#dashboard-kpi-drawer", "Cash in drawer")
    assert has_element?(manager_view, "#dashboard-kpi-tickets", "Orders Completed")
    assert has_element?(manager_view, "#dashboard-panel-top-item", "Espresso")
    assert has_element?(manager_view, "#dashboard-panel-top-item", "1 sold")
    refute has_element?(manager_view, "#dashboard-panel-reports")
    refute has_element?(manager_view, "#staff-home-kpi-unpaid")
    refute has_element?(manager_view, "#staff-home-open-shop")
    refute has_element?(manager_view, "#owner-dashboard")
    refute has_element?(manager_view, "#dashboard-kpi-staff-shift")
    refute has_element?(manager_view, "#staff-home-shop-open")
    refute has_element?(manager_view, "#staff-home-close")
    refute has_element?(manager_view, "#staff-home-today-barista")
    refute has_element?(manager_view, "#staff-home-chart")

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
    assert has_element?(barista_view, "#staff-home-kpi-active")
    assert has_element?(barista_view, "#staff-home-pos", "Open POS")
    assert has_element?(barista_view, "#staff-home-orders", "Orders")
    assert has_element?(barista_view, "#staff-home-kpi-unpaid", "Unpaid")
    refute has_element?(barista_view, "#staff-home-open-shop")
    assert has_element?(barista_view, "#staff-home-my-shifts", "My shifts")
    refute has_element?(barista_view, "#staff-home-unpaid")

    assert {:ok, _} = Shifts.record_close(manager, %{counted_cash: "75"})

    {:ok, closed_view, _html} = live(manager_conn, ~p"/staff")
    assert has_element?(closed_view, "#staff-home-shift-closed", "Closed")
    assert has_element?(closed_view, "#staff-home-drawer", "Drawer · sealed")
    assert has_element?(closed_view, "#staff-home-drawer", "Counted")
    assert has_element?(closed_view, "#staff-home-drawer-variance", "Even")
    assert has_element?(closed_view, "#staff-home-drawer-close", "View close")
    assert has_element?(closed_view, "#staff-home-reports", "View reports")
    refute has_element?(closed_view, "#staff-home-pos")
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

    {:ok, view, _html} = live(manager_conn, ~p"/staff")
    assert has_element?(view, "#staff-home-paid-breakdown", "Payment methods")
    assert has_element?(view, "#staff-home-paid-breakdown", "Maya")
    assert has_element?(view, "#staff-home-paid-breakdown", "₱95")
    refute has_element?(view, "#staff-home-paid-breakdown", "PayMongo")
    assert has_element?(view, "#staff-home-paid-breakdown .staff-paid-breakdown-swatch")
    assert render(view) =~ "--mix-color: #c4a574"
    refute has_element?(view, "#staff-home-chart")
    refute has_element?(view, "#staff-home-mix-empty")
    assert has_element?(view, "#dashboard-kpi-tickets", "1")
    assert has_element?(view, "#staff-home-pos", "Open POS")
    assert has_element?(view, "#dashboard-panel-top-item", "Americano")
    refute has_element?(view, "#dashboard-panel-reports")
    refute has_element?(view, "#staff-home-paid-breakdown a", "Close shift")
    refute has_element?(view, "#dashboard-panel-transactions")
  end

  test "owner dashboard shows staff on shift and paid sales trends", %{conn: conn} do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner Dash",
        email: "owner-dash-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 2, price: Decimal.new("140")}],
        %{customer_name: "Owner Guest", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(order, paid_via: "cash")

    owner_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, owner.id)

    {:ok, view, _html} = live(owner_conn, ~p"/staff")
    assert has_element?(view, "#owner-dashboard")
    assert has_element?(view, "#staff-account-toggle", "Owner Dash")
    assert has_element?(view, "#staff-home-greeting", "Owner Dash")
    assert has_element?(view, "#owner-dash-aside[phx-hook='OwnerDashRail']")
    assert has_element?(view, "#staff-home-kpis.owner-kpi-grid")
    assert has_element?(view, "#owner-dash-nav-group-counter", "Counter")
    assert has_element?(view, "#owner-dash-nav-group-manage", "Manage")
    assert has_element?(view, "#owner-dash-nav-home", "Home")
    assert has_element?(view, "#owner-dash-nav-logout", "Log out")
    assert has_element?(view, "#dashboard-panel-sales", "Total Sales Today")
    assert has_element?(view, "#dashboard-kpi-tickets", "Orders Completed")
    assert has_element?(view, "#dashboard-panel-top-item", "Latte")
    assert has_element?(view, "#dashboard-kpi-staff-shift", "Active Staff on Shift")
    assert has_element?(view, "#dashboard-kpi-staff-shift", "0")
    refute has_element?(view, "#dashboard-kpi-drawer")
    assert has_element?(view, "#owner-sales-trends", "Sales Trends")
    assert has_element?(view, "#owner-sales-trends[phx-hook='OwnerSalesTrend']")
    assert has_element?(view, "#owner-trends-line")
    assert has_element?(view, "#owner-sales-trends", "₱0")
    assert has_element?(view, "#owner-chart-daily")
    assert has_element?(view, "#owner-chart-weekly")
    assert has_element?(view, "#owner-chart-monthly")
    refute has_element?(view, "#staff-home-kpi-unpaid")
    refute has_element?(view, "#staff-home-pos")
    refute has_element?(view, "#staff-home-printer")
    assert has_element?(view, ".owner-home-boards #staff-home-paid-breakdown", "Cash")
    refute has_element?(view, "#staff-home-paid-breakdown", "PayMongo")
    assert has_element?(view, ".owner-board-stack #staff-home-today", "Drawer")
    assert has_element?(view, ".owner-home-boards #dashboard-panel-popular-products")
    assert has_element?(view, ".owner-home-boards #dashboard-panel-payout", "Payout today")
    refute has_element?(view, "#dashboard-panels")
    assert has_element?(view, "#staff-home-paid-breakdown .dashboard-donut")
    assert has_element?(view, "#staff-home-paid-breakdown .staff-paid-breakdown-swatch")
    assert render(view) =~ "--mix-color: #394331"
    assert chronological_trend_dates?(view)

    view |> element("#owner-chart-weekly") |> render_click()
    assert has_element?(view, "#owner-chart-weekly.is-active")
    assert has_element?(view, "#owner-trends-line")
    assert chronological_trend_dates?(view)

    view |> element("#owner-chart-monthly") |> render_click()
    assert has_element?(view, "#owner-chart-monthly.is-active")
    assert has_element?(view, "#owner-sales-trends")
    assert has_element?(view, "#owner-sales-trends", "₱0")
    assert chronological_trend_dates?(view)
  end

  @tag :without_shop_open
  test "not-open home makes opening cash the only launch action", %{conn: conn} do
    {:ok, manager} =
      Accounts.register_user(%{
        name: "Open",
        email: "open-home-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    manager_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, manager.id)

    {:ok, view, _html} = live(manager_conn, ~p"/staff")
    assert has_element?(view, "#staff-home-shop-open", "Opening cash required")
    assert has_element?(view, "#staff-home-open-shop", "Enter opening cash")
    refute has_element?(view, "#staff-home-pos")
    refute has_element?(view, "#staff-home-shop-open-link")
    refute has_element?(view, "#staff-home-today")
    assert has_element?(view, "#dashboard-kpi-drawer", "Cash in drawer")
  end

  test "unpaid KPI shows today's unpaid count and updates after mark_paid", %{conn: conn} do
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

    assert has_element?(view, "#staff-home-kpi-unpaid", "Unpaid")
    assert has_element?(view, "#staff-home-kpi-unpaid strong", "1")
    refute has_element?(view, "#staff-home-unpaid")

    {:ok, _} = Orders.mark_paid(unpaid, paid_via: "cash")

    wait_for_home_reload(view)

    assert has_element?(view, "#staff-home-kpi-unpaid", "Unpaid")
    assert has_element?(view, "#staff-home-kpi-unpaid strong", "0")
  end

  test "unpaid KPI is zero when there are no unpaid orders", %{conn: conn} do
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

    assert has_element?(view, "#staff-home-kpi-unpaid", "Unpaid")
    assert has_element?(view, "#staff-home-kpi-unpaid strong", "0")
    refute has_element?(view, "#staff-home-unpaid")
  end

  defp chronological_trend_dates?(view) do
    dates =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find(".owner-trends-x [data-date]")
      |> Enum.map(fn node ->
        node
        |> Floki.attribute("data-date")
        |> List.first()
      end)
      |> Enum.reject(&(&1 in [nil, ""]))

    dates == Enum.sort(dates)
  end

  defp wait_for_home_reload(view) do
    ms = Application.get_env(:espreso, :staff_pubsub_reload_debounce_ms, 300)
    Process.sleep(ms + 50)
    _ = :sys.get_state(view.pid)
    :ok
  end
end
