defmodule EspresoWeb.StaffAuthTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Auth.PinAttemptLimiter
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift
  alias Espreso.Repo

  import Ecto.Query

  setup do
    PinAttemptLimiter.reset!()

    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Manager",
        email: "manager@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Staff",
        email: "barista@test.local",
        password: "password123",
        role: "barista"
      })

    %{owner: owner, manager: manager, barista: barista}
  end

  test "staff home and orders require login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/staff")
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/orders")
  end

  test "login lands all staff on home", %{
    conn: conn,
    barista: barista,
    manager: manager,
    owner: owner
  } do
    conn =
      post(conn, ~p"/session", %{
        "user" => %{"email" => barista.email, "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/staff"

    conn =
      post(recycle(conn), ~p"/session", %{
        "user" => %{"email" => manager.email, "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/staff"

    conn =
      post(recycle(conn), ~p"/session", %{
        "user" => %{"email" => owner.email, "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/staff"
  end

  test "/register redirects to login when accounts already exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/login"}}} = live(conn, ~p"/register")
  end

  test "public register cannot create staff after initialization", %{conn: conn} do
    assert {:error, :registration_closed} =
             Accounts.register_self(%{
               "name" => "New Staff",
               "email" => "newstaff@test.local",
               "password" => "password123",
               "role" => "barista"
             })

    assert {:error, {:live_redirect, %{to: "/login"}}} = live(conn, ~p"/register")
  end

  test "dashboard requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/dashboard")
  end

  test "/dashboard redirects staff to Home", %{conn: conn, owner: owner, barista: barista} do
    assert {:error, {:live_redirect, %{to: "/staff"}}} = live(log_in(conn, owner), ~p"/dashboard")

    assert {:error, {:live_redirect, %{to: "/staff"}}} =
             live(log_in(conn, barista), ~p"/dashboard")
  end

  test "authenticated staff can open role-aware home dashboard", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/staff")
    assert has_element?(owner_view, ".staff-shell-title", "Home")
    assert has_element?(owner_view, "#staff-pos-rail.staff-pos-rail--bar")
    refute has_element?(owner_view, "#staff-shell")
    assert has_element?(owner_view, "#staff-pos-rail #staff-notifications")
    html = render(owner_view)

    assert html
           |> :binary.match("id=\"staff-nav-menu-open\"")
           |> elem(0) <
             html |> :binary.match("id=\"staff-nav-logo\"") |> elem(0)

    assert has_element?(owner_view, "#staff-nav-orders", "Orders")
    assert has_element?(owner_view, "#staff-nav-pos", "POS")
    assert has_element?(owner_view, "#staff-nav-home.is-active", "Home")
    refute has_element?(owner_view, "#staff-nav-dashboard")
    assert has_element?(owner_view, "#staff-nav-availability", "Availability")
    assert has_element?(owner_view, "#staff-nav-staff", "Staff")
    assert has_element?(owner_view, "#staff-nav-settings", "Settings")
    assert has_element?(owner_view, "#dashboard-panel-sales", "Paid today")
    assert has_element?(owner_view, "#staff-home-paid-breakdown", "Payment methods")
    refute has_element?(owner_view, "#staff-home-paid-breakdown a", "Close shift")
    refute has_element?(owner_view, "#dashboard-panel-orders")
    refute has_element?(owner_view, "#dashboard-panel-transactions")
    refute has_element?(owner_view, "#dashboard-panel-close-shift")
    refute has_element?(owner_view, "#dashboard-todays-orders-preview")
    assert has_element?(owner_view, "#dashboard-panel-popular-products", "Popular Products")
    assert has_element?(owner_view, "#dashboard-panel-reports", "Reports")
    refute has_element?(owner_view, "#dashboard-panel-staff-activity")
    refute render(owner_view) =~ "Coming soon"
    refute render(owner_view) =~ "86 sold-out"

    refute has_element?(owner_view, "#dashboard-panel-users")
    refute has_element?(owner_view, "#dashboard-panel-settings")
    refute has_element?(owner_view, "#dashboard-panel-availability")

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/staff")
    assert has_element?(manager_view, "#dashboard-panel-sales", "Paid today")
    assert has_element?(manager_view, "#staff-home-paid-breakdown", "Payment methods")
    refute has_element?(manager_view, "#dashboard-panel-orders")
    refute has_element?(manager_view, "#dashboard-panel-transactions")
    refute has_element?(manager_view, "#dashboard-panel-close-shift")
    refute has_element?(manager_view, "#dashboard-panel-availability")
    refute has_element?(manager_view, "#dashboard-todays-orders-preview")
    refute render(manager_view) =~ "86 sold-out"

    assert has_element?(manager_view, "#dashboard-panel-reports", "Reports")
    refute has_element?(manager_view, "#dashboard-panel-users")
    refute has_element?(manager_view, "#dashboard-panel-settings")
    refute has_element?(manager_view, "#dashboard-panel-popular-products")

    {:ok, staff_view, _html} = live(log_in(conn, barista), ~p"/staff")
    refute has_element?(staff_view, "#staff-nav-dashboard")
    refute has_element?(staff_view, "#staff-nav-availability")
    refute has_element?(staff_view, "#staff-nav-staff")
    refute has_element?(staff_view, "#staff-nav-settings")
    assert has_element?(staff_view, "#staff-nav-orders", "Orders")
    assert has_element?(staff_view, "#staff-nav-pos", "POS")
    refute has_element?(staff_view, "#dashboard-panel-todays-orders")
    refute has_element?(staff_view, "#dashboard-todays-orders-preview")
    refute has_element?(staff_view, "#dashboard-staff-note")
    assert has_element?(staff_view, "#staff-home-kpi-active")
    refute has_element?(staff_view, "#dashboard-panel-sales")
    refute has_element?(staff_view, "#staff-home-paid-breakdown")
    refute has_element?(staff_view, "#dashboard-panels")
    refute has_element?(staff_view, "#dashboard-panel-reports")
    refute has_element?(staff_view, "#dashboard-panel-settings")
    refute has_element?(staff_view, "#dashboard-panel-availability")
    refute has_element?(staff_view, "#dashboard-panel-transactions")
  end

  test "dashboard does not duplicate the Orders hub", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    alias Espreso.Orders

    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, _} =
      Orders.create_order(lines, %{
        customer_name: "Ava",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, preparing} =
      Orders.create_order(lines, %{
        customer_name: "Ben",
        fulfillment: :pickup,
        payment_method: :counter
      })

    assert {:ok, _} = Orders.mark_paid(preparing)
    {:ok, _} = Orders.update_status(preparing, "preparing")

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/staff")
    refute has_element?(owner_view, "#dashboard-panel-orders")
    refute has_element?(owner_view, "#dashboard-todays-orders-preview")

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/staff")
    refute has_element?(manager_view, "#dashboard-panel-orders")
    refute has_element?(manager_view, "#dashboard-todays-orders-preview")

    {:ok, staff_view, _html} = live(log_in(conn, barista), ~p"/staff")
    refute has_element?(staff_view, "#dashboard-panel-todays-orders")
    refute has_element?(staff_view, "#dashboard-todays-orders-preview")
    assert has_element?(staff_view, "#staff-home-orders")
  end

  test "dashboard Sales panel shows paid overview for owner and manager only", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    alias Espreso.Menu
    alias Espreso.Orders

    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, paid} =
      Orders.create_order(lines, %{
        customer_name: "Paid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(paid)

    {:ok, _unpaid} =
      Orders.create_order(
        [%{name: "Americano", size: "12oz", quantity: 1, price: Decimal.new("120")}],
        %{
          customer_name: "Unpaid",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    expected_body = "#{Menu.format_price(Decimal.new("75"))} today · 1 paid orders"

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/staff")

    assert has_element?(
             owner_view,
             "#dashboard-panel-sales .staff-home-card-body",
             expected_body
           )

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/staff")

    assert has_element?(
             manager_view,
             "#dashboard-panel-sales .staff-home-card-body",
             expected_body
           )

    {:ok, staff_view, _html} = live(log_in(conn, barista), ~p"/staff")
    refute has_element?(staff_view, "#dashboard-panel-sales")
  end

  test "dashboard Popular Products is owner-only with real or empty data", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    alias Espreso.Orders

    {:ok, owner_empty, _html} = live(log_in(conn, owner), ~p"/staff")

    assert has_element?(
             owner_empty,
             "#dashboard-panel-popular-products .staff-home-card-body",
             "No paid product sales today."
           )

    {:ok, manager_empty, _html} = live(log_in(conn, manager), ~p"/staff")
    refute has_element?(manager_empty, "#dashboard-panel-popular-products")

    {:ok, staff_empty, _html} = live(log_in(conn, barista), ~p"/staff")
    refute has_element?(staff_empty, "#dashboard-panel-popular-products")

    {:ok, paid} =
      Orders.create_order(
        [
          %{name: "Americano", size: "12oz", quantity: 3, price: Decimal.new("120")},
          %{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}
        ],
        %{customer_name: "Pop", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(paid)

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/staff")

    assert has_element?(owner_view, "#dashboard-panel-popular-products .dashboard-popular-list")
    assert has_element?(owner_view, "#dashboard-panel-popular-products td", "Americano")
    assert has_element?(owner_view, "#dashboard-panel-popular-products td", "Espresso")

    assert has_element?(
             owner_view,
             "#dashboard-panel-popular-products .dashboard-popular-qty",
             "3"
           )

    assert has_element?(
             owner_view,
             "#dashboard-panel-popular-products .dashboard-popular-qty",
             "1"
           )

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/staff")
    refute has_element?(manager_view, "#dashboard-panel-popular-products")

    {:ok, staff_view, _html} = live(log_in(conn, barista), ~p"/staff")
    refute has_element?(staff_view, "#dashboard-panel-popular-products")
  end

  test "dashboard Reports panel shows last-7-days paid sales for owner and manager", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    alias Espreso.Menu
    alias Espreso.Orders

    {:ok, owner_empty, _html} = live(log_in(conn, owner), ~p"/staff")

    assert has_element?(
             owner_empty,
             "#dashboard-panel-reports .staff-home-card-body",
             "No paid sales in the last 7 days."
           )

    {:ok, manager_empty, _html} = live(log_in(conn, manager), ~p"/staff")

    assert has_element?(
             manager_empty,
             "#dashboard-panel-reports .staff-home-card-body",
             "No paid sales in the last 7 days."
           )

    {:ok, staff_empty, _html} = live(log_in(conn, barista), ~p"/staff")
    refute has_element?(staff_empty, "#dashboard-panel-reports")

    {:ok, paid} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Report Paid", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(paid)

    expected_body = "#{Menu.format_price(Decimal.new("75"))} last 7 days · 1 paid orders"

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/staff")

    assert has_element?(
             owner_view,
             "#dashboard-panel-reports .staff-home-card-body",
             expected_body
           )

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/staff")

    assert has_element?(
             manager_view,
             "#dashboard-panel-reports .staff-home-card-body",
             expected_body
           )

    {:ok, staff_view, _html} = live(log_in(conn, barista), ~p"/staff")
    refute has_element?(staff_view, "#dashboard-panel-reports")
  end

  test "dashboard is sales-only and does not preview the order queue", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    alias Espreso.Orders

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Cora",
          fulfillment: :dine_in,
          table_number: "8",
          payment_method: :counter
        }
      )

    assert {:ok, _} = Orders.mark_paid(order)
    {:ok, preparing} = Orders.update_status(order, "preparing")

    for user <- [owner, manager, barista] do
      {:ok, view, _html} = live(log_in(conn, user), ~p"/staff")
      refute has_element?(view, "#dashboard-todays-orders-preview")
      refute has_element?(view, "#dashboard-preview-order-#{preparing.id}")
    end
  end

  test "/staff shows role-aware shortcuts", %{
    conn: conn,
    barista: barista,
    manager: manager,
    owner: owner
  } do
    {:ok, barista_view, _html} = live(log_in(conn, barista), ~p"/staff")
    assert has_element?(barista_view, ".staff-shell-title", "Home")
    assert has_element?(barista_view, "#staff-pos-rail.staff-pos-rail--bar")
    refute has_element?(barista_view, "#staff-shell")
    assert has_element?(barista_view, "#staff-pos-rail #staff-notifications")
    assert has_element?(barista_view, "#staff-nav-home.is-active")
    assert has_element?(barista_view, "#staff-home-identity")
    assert has_element?(barista_view, "#staff-home-greeting")
    assert render(barista_view) =~ ~r/Good (morning|afternoon|evening), /
    assert has_element?(barista_view, "#staff-home-pos", "Open POS")
    assert has_element?(barista_view, "#staff-home-orders", "Orders")
    assert has_element?(barista_view, "#staff-home-unpaid", "Unpaid")
    assert has_element?(barista_view, "#staff-home-my-shifts", "My shifts")
    refute has_element?(barista_view, "#staff-home-dashboard")
    refute has_element?(barista_view, "#staff-home-today")
    refute has_element?(barista_view, "#staff-home-close")
    refute has_element?(barista_view, "#staff-home-cash-out")
    refute has_element?(barista_view, "#staff-home-transactions")
    refute has_element?(barista_view, "#staff-home-customers")
    assert has_element?(barista_view, "#staff-nav-close", "Close shift")
    refute has_element?(barista_view, "#staff-home-shop-status")
    refute has_element?(barista_view, ".staff-home-shortcut-eyebrow")

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/staff")
    assert has_element?(manager_view, "#staff-home-today")
    assert has_element?(manager_view, "#staff-home-pos", "Open POS")
    assert has_element?(manager_view, "#staff-home-orders", "Orders")
    refute has_element?(manager_view, "#staff-home-dashboard")
    refute has_element?(manager_view, "#staff-home-availability")
    refute has_element?(manager_view, "#staff-home-close")
    refute has_element?(manager_view, "#staff-nav-dashboard")
    assert has_element?(manager_view, "#staff-nav-close", "Close shift")

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/staff")
    refute has_element?(owner_view, "#staff-home-staff")
    refute has_element?(owner_view, "#staff-home-settings")
    assert has_element?(owner_view, "#staff-nav-staff", "Staff")
    assert has_element?(owner_view, "#staff-nav-settings", "Settings")
    assert has_element?(owner_view, "#staff-nav-close", "Close shift")
  end

  test "orders shell is active for barista with Orders and POS only", %{
    conn: conn,
    barista: barista
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/orders")

    assert has_element?(view, ".staff-shell-title", "Orders")
    assert has_element?(view, "#staff-nav-orders.is-active", "Orders")
    assert has_element?(view, "#staff-nav-pos", "POS")
    assert has_element?(view, "#staff-nav-home", "Home")
    assert has_element?(view, "#staff-nav-menu-open")
    assert has_element?(view, "#staff-nav-drawer")
    assert has_element?(view, "#staff-nav-drawer-panel #staff-nav-logout", "Log out")
    assert has_element?(view, "#staff-nav-logout", "Log out")
    refute has_element?(view, "#staff-nav-more")
    refute has_element?(view, "#staff-shell-more")
    refute has_element?(view, "#staff-nav-dashboard")
    refute has_element?(view, "#staff-nav-staff")
  end

  test "home menu drawer lists secondary destinations", %{
    conn: conn,
    barista: barista
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/staff")

    assert has_element?(view, "#staff-nav-menu-open")
    assert has_element?(view, "#staff-nav-drawer-panel")
    assert has_element?(view, "#staff-nav-drawer-role", "Staff")
    refute render(view) =~ "Staff Menu"
    refute render(view) =~ "Manager Menu"
    refute render(view) =~ "Owner Menu"
    assert has_element?(view, "#staff-nav-drawer-panel #staff-nav-transactions", "Transactions")
    assert has_element?(view, "#staff-nav-drawer-panel #staff-nav-customers", "Customers")
    assert has_element?(view, "#staff-nav-drawer-group-service", "Service")
    assert has_element?(view, "#staff-nav-drawer-group-shift", "Shift")
    refute has_element?(view, "#staff-nav-drawer-group-manage")
    assert has_element?(view, "#staff-nav-drawer-panel #staff-nav-my_shifts", "My shifts")
    assert has_element?(view, "#staff-nav-drawer-panel #staff-nav-cash_out", "Cash Out")
    assert has_element?(view, "#staff-nav-drawer-panel #staff-nav-close", "Close shift")
    assert has_element?(view, "#staff-nav-drawer-panel #staff-nav-logout", "Log out")
    refute has_element?(view, "#staff-nav-dashboard")
    refute has_element?(view, "#staff-nav-reports")

    view |> element("#staff-nav-menu-open") |> render_click()
    assert has_element?(view, "#staff-nav-drawer-panel.is-open")
    assert has_element?(view, "#staff-nav-drawer-backdrop")
    assert has_element?(view, "#staff-nav-menu-close")

    view |> element("#staff-nav-menu-close") |> render_click()
    refute has_element?(view, "#staff-nav-drawer-panel.is-open")
    refute has_element?(view, "#staff-nav-drawer-backdrop")
  end

  test "drawer header shows role title without Menu for each role", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/staff")
    assert has_element?(owner_view, "#staff-nav-drawer-role", "Owner")
    refute render(owner_view) =~ "Owner Menu"
    refute render(owner_view) =~ "Staff Menu"
    refute render(owner_view) =~ "Manager Menu"

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/staff")
    assert has_element?(manager_view, "#staff-nav-drawer-role", "Manager")
    refute render(manager_view) =~ "Manager Menu"
    refute render(manager_view) =~ "Staff Menu"
    refute render(manager_view) =~ "Owner Menu"

    {:ok, barista_view, _html} = live(log_in(conn, barista), ~p"/staff")
    assert has_element?(barista_view, "#staff-nav-drawer-role", "Staff")
    refute render(barista_view) =~ "Staff Menu"
    refute render(barista_view) =~ "Manager Menu"
    refute render(barista_view) =~ "Owner Menu"
  end

  test "drawer groups secondary destinations by Service, Shift, and Manage", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    {:ok, barista_view, _html} = live(log_in(conn, barista), ~p"/staff")
    assert has_element?(barista_view, "#staff-nav-drawer-group-counter", "Counter")
    assert has_element?(barista_view, "#staff-nav-drawer-group-service", "Service")
    assert has_element?(barista_view, "#staff-nav-drawer-group-shift", "Shift")
    refute has_element?(barista_view, "#staff-nav-drawer-group-manage")
    refute has_element?(barista_view, "#staff-nav-attendance")

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/staff")
    assert has_element?(manager_view, "#staff-nav-drawer-group-service", "Service")
    assert has_element?(manager_view, "#staff-nav-drawer-group-shift", "Shift")
    assert has_element?(manager_view, "#staff-nav-drawer-group-manage", "Manage")
    refute has_element?(manager_view, "#staff-nav-dashboard")

    assert has_element?(
             manager_view,
             "#staff-nav-drawer-group-manage #staff-nav-reports",
             "Reports"
           )

    assert has_element?(
             manager_view,
             "#staff-nav-drawer-group-manage #staff-nav-availability",
             "Availability"
           )

    refute has_element?(manager_view, "#staff-nav-staff")
    refute has_element?(manager_view, "#staff-nav-settings")
    refute has_element?(manager_view, "#staff-nav-my_shifts")

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/staff")
    assert has_element?(owner_view, "#staff-nav-drawer-group-manage #staff-nav-staff", "Staff")

    assert has_element?(
             owner_view,
             "#staff-nav-drawer-group-manage #staff-nav-settings",
             "Settings"
           )
  end

  test "manager can access staff routes but not user management", %{
    conn: conn,
    manager: manager
  } do
    conn = log_in(conn, manager)

    {:ok, orders, _html} = live(conn, ~p"/orders")
    assert has_element?(orders, ".staff-shell-title", "Orders")
    refute has_element?(orders, "#staff-nav-dashboard")
    assert has_element?(orders, "#staff-nav-availability", "Availability")
    refute has_element?(orders, "#staff-nav-staff")

    assert {:error, {:redirect, %{to: "/staff"}}} = live(conn, ~p"/admin/users")
  end

  test "owner can open staff admin from shell", %{conn: conn, owner: owner} do
    conn = log_in(conn, owner)
    {:ok, admin, _html} = live(conn, ~p"/admin/users")
    assert has_element?(admin, ".staff-shell-title", "Staff")
    assert has_element?(admin, "#staff-nav-staff.is-active", "Staff")
    assert has_element?(admin, "#staff-nav-menu-open.is-active")
  end

  test "staff cannot open admin users", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    assert {:error, {:redirect, %{to: "/staff"}}} = live(conn, ~p"/admin/users")
  end

  test "owner cannot edit own role in admin UI", %{conn: conn, owner: owner} do
    conn = log_in(conn, owner)
    {:ok, view, _html} = live(conn, ~p"/admin/users")

    view
    |> element(~s(button[phx-click="edit"][phx-value-id="#{owner.id}"]))
    |> render_click()

    refute has_element?(view, "#edit-user-#{owner.id} select[name='user[role]']")
    assert has_element?(view, "#edit-user-#{owner.id}")
  end

  test "pos is reachable for staff", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    {:ok, view, _html} = live(conn, ~p"/pos")
    assert has_element?(view, ".staff-shell-title", "POS")
    assert has_element?(view, "#staff-nav-pos.is-active", "POS")
    assert has_element?(view, "#pos-catalog")
    refute render(view) =~ "Coming soon"
  end

  test "pin login lands barista on home", %{conn: conn, barista: barista} do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")

    conn =
      post(conn, ~p"/session/pin", %{
        "user_id" => barista.id,
        "pin" => "4321"
      })

    assert redirected_to(conn) == ~p"/staff"
  end

  test "pin login accepts string user_id from form", %{conn: conn, barista: barista} do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")

    conn =
      post(conn, ~p"/session/pin", %{
        "user_id" => to_string(barista.id),
        "pin" => "4321"
      })

    assert redirected_to(conn) == ~p"/staff"
  end

  test "invalid pin login returns to login", %{conn: conn, barista: barista} do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")

    conn =
      post(conn, ~p"/session/pin", %{
        "user_id" => barista.id,
        "pin" => "9999"
      })

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Incorrect PIN. Try again."
  end

  test "unified login shows ELIlai branding and pin flow without role selector", %{
    conn: conn,
    barista: barista
  } do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")

    {:ok, view, html} = live(conn, ~p"/login")
    assert html =~ "Welcome back"
    assert html =~ "Please login to your account"
    assert html =~ "Elilai Kafe"

    assert has_element?(
             view,
             "header.staff-auth-brand source[type='image/webp'][srcset='/images/elilai-kafe/elilai-kafe-mark-login.webp']"
           )

    assert has_element?(
             view,
             "header.staff-auth-brand img.staff-auth-logo[src='/images/elilai-kafe/elilai-kafe-mark-login.png'][width='512'][height='512']"
           )

    assert has_element?(view, "header.staff-auth-brand p.staff-auth-wordmark", "ELILAI KAFE")
    refute html =~ "/images/elilai-kafe/elilai-kafe-mark.png"

    assert has_element?(view, ".staff-auth-page--approved")
    assert has_element?(view, ".staff-auth-stage")
    assert has_element?(view, "aside.staff-auth-visual img.staff-auth-visual-img")

    assert has_element?(
             view,
             "aside.staff-auth-visual source[type='image/webp'][srcset='/images/elilai-kafe/login-brand-panel.webp']"
           )

    assert has_element?(
             view,
             "aside.staff-auth-visual img.staff-auth-visual-img[src='/images/elilai-kafe/login-brand-panel.jpg'][width='1084'][height='1310']"
           )

    assert has_element?(view, "#staff-pin-login")
    assert has_element?(view, "#staff-roster-search")
    assert has_element?(view, "#staff-pin-local[phx-hook='StaffPinPad']")
    assert has_element?(view, "#staff-auth-account-recovery", "Account recovery")
    refute has_element?(view, ".staff-auth-register")
    refute html =~ ~r/href=\"\/register\"/
    assert has_element?(view, ".staff-auth-actions #staff-pin-submit", "Sign in")
    refute html =~ "/images/coffeespot/"
    refute html =~ "find coffee"
    refute html =~ "Sign in with Google"
    refute has_element?(view, ".staff-auth-visual-tagline")

    refute html =~ "Employee login"
    refute html =~ "Owner login"
    refute html =~ "Manager Login"
    refute html =~ "Start Shift"
    refute html =~ "Owner / manager email login"
    refute has_element?(view, "select[name='role']")
    refute has_element?(view, "#staff-login-form")

    view |> element("#staff-roster-search") |> render_change(%{"q" => ""})

    assert has_element?(
             view,
             "#staff-roster-dropdown #staff-pin-user-#{barista.id}",
             barista.name
           )

    assert has_element?(view, "#staff-pin-form button.staff-auth-submit--shift", "Sign in")
  end

  test "staff login search filters roster and empty search copy", %{
    conn: conn,
    barista: barista,
    manager: manager
  } do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")
    assert {:ok, _} = Accounts.set_pin(manager, "5678")

    {:ok, view, _html} = live(conn, ~p"/login")

    view |> element("#staff-roster-search") |> render_change(%{"q" => ""})

    assert has_element?(view, "#staff-roster-dropdown #staff-pin-user-#{barista.id}")
    assert has_element?(view, "#staff-roster-dropdown #staff-pin-user-#{manager.id}")

    view
    |> element("#staff-roster-search")
    |> render_change(%{"q" => barista.name})

    assert has_element?(view, "#staff-roster-dropdown #staff-pin-user-#{barista.id}")
    refute has_element?(view, "#staff-roster-dropdown #staff-pin-user-#{manager.id}")

    html =
      view
      |> element("#staff-roster-search")
      |> render_change(%{"q" => "zzz-no-match"})

    assert html =~ "No matching team members."
  end

  test "staff pin login selects user and prepares client pin pad", %{conn: conn, barista: barista} do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")

    {:ok, view, _html} = live(conn, ~p"/login")

    view |> element("#staff-roster-search") |> render_change(%{"q" => ""})
    view |> element("#staff-pin-user-#{barista.id}") |> render_click()

    assert has_element?(view, "#staff-pin-selected", barista.name)
    assert has_element?(view, "#staff-pin-enter-hint", "Enter your PIN.")
    assert has_element?(view, "#staff-pin-local[data-pin-ready='true']")
    assert has_element?(view, "#staff-pin-local[data-staff-id='#{barista.id}']")
    assert has_element?(view, "#staff-pin-form input[name='user_id'][value='#{barista.id}']")
    assert has_element?(view, "#staff-pin-local input[name='pin']")
    assert has_element?(view, "button[data-pin-key='1']")
    assert has_element?(view, "button[data-pin-action='clear']")
    assert has_element?(view, "button[data-pin-action='backspace']")
    assert has_element?(view, "#staff-pin-form button.staff-auth-submit--shift[data-pin-submit]")
    refute has_element?(view, "button[phx-click='pin_digit']")
  end

  test "account recovery reveals email password form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/login")

    view |> element("#staff-auth-account-recovery") |> render_click()

    assert has_element?(view, "h1.staff-auth-title", "Account recovery")
    assert has_element?(view, "#staff-login-form")
    assert has_element?(view, "#staff-auth-back-to-pin", "Back to sign in")
    refute has_element?(view, "#staff-pin-login")
  end

  test "empty pin roster shows owner pin setup message", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/login")

    assert html =~ "No PINs configured. Ask an owner to set staff PINs."
    assert has_element?(view, "#staff-pin-roster-empty")
  end

  test "pin login preserves manager and owner destinations", %{
    conn: conn,
    manager: manager,
    owner: owner
  } do
    assert {:ok, _} = Accounts.set_pin(manager, "5678")
    assert {:ok, _} = Accounts.set_pin(owner, "9012")

    manager_conn =
      post(conn, ~p"/session/pin", %{
        "user_id" => manager.id,
        "pin" => "5678"
      })

    assert redirected_to(manager_conn) == ~p"/staff"
    assert get_session(manager_conn, :user_id) == manager.id

    owner_conn =
      post(recycle(conn), ~p"/session/pin", %{
        "user_id" => owner.id,
        "pin" => "9012"
      })

    assert redirected_to(owner_conn) == ~p"/staff"
    assert get_session(owner_conn, :user_id) == owner.id
  end

  test "logout returns to unified login", %{conn: conn, barista: barista} do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")

    logged_in =
      post(conn, ~p"/session/pin", %{
        "user_id" => barista.id,
        "pin" => "4321"
      })

    assert redirected_to(logged_in) == ~p"/staff"

    logged_out = delete(recycle(logged_in), ~p"/logout")
    assert redirected_to(logged_out) == ~p"/login"

    {:ok, _view, html} = live(recycle(logged_out), ~p"/login")
    assert html =~ "Welcome back"
    assert html =~ "Please login to your account"
  end

  test "repeated wrong pins trigger cooldown without locking other staff", %{
    conn: conn,
    barista: barista,
    manager: manager
  } do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")
    assert {:ok, _} = Accounts.set_pin(manager, "5678")

    Enum.each(1..5, fn _ ->
      conn =
        post(recycle(conn), ~p"/session/pin", %{
          "user_id" => barista.id,
          "pin" => "0000"
        })

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Incorrect PIN. Try again."
    end)

    limited =
      post(recycle(conn), ~p"/session/pin", %{
        "user_id" => barista.id,
        "pin" => "0000"
      })

    assert redirected_to(limited) == ~p"/login"

    assert Phoenix.Flash.get(limited.assigns.flash, :error) ==
             "Too many attempts. Please wait a moment before trying again."

    other =
      post(recycle(conn), ~p"/session/pin", %{
        "user_id" => manager.id,
        "pin" => "5678"
      })

    assert redirected_to(other) == ~p"/staff"
    assert get_session(other, :user_id) == manager.id
  end

  test "successful pin login resets user throttle state", %{conn: conn, barista: barista} do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")

    Enum.each(1..4, fn _ ->
      post(recycle(conn), ~p"/session/pin", %{
        "user_id" => barista.id,
        "pin" => "0000"
      })
    end)

    ok =
      post(recycle(conn), ~p"/session/pin", %{
        "user_id" => barista.id,
        "pin" => "4321"
      })

    assert redirected_to(ok) == ~p"/staff"

    Enum.each(1..5, fn _ ->
      post(recycle(conn), ~p"/session/pin", %{
        "user_id" => barista.id,
        "pin" => "0000"
      })
    end)

    limited =
      post(recycle(conn), ~p"/session/pin", %{
        "user_id" => barista.id,
        "pin" => "1111"
      })

    assert Phoenix.Flash.get(limited.assigns.flash, :error) ==
             "Too many attempts. Please wait a moment before trying again."
  end

  describe "staff shift attendance on browser auth" do
    test "successful pin login opens exactly one staff shift", %{conn: conn, barista: barista} do
      assert {:ok, _} = Accounts.set_pin(barista, "4321")

      conn =
        post(conn, ~p"/session/pin", %{
          "user_id" => barista.id,
          "pin" => "4321"
        })

      assert redirected_to(conn) == ~p"/staff"
      assert get_session(conn, :user_id) == barista.id

      open = StaffShifts.get_open_shift(barista)
      assert %StaffShift{} = open
      assert open.user_id == barista.id
      assert is_nil(open.ended_at)
      assert shift_count(barista.id) == 1
    end

    test "failed pin login creates no staff shift", %{conn: conn, barista: barista} do
      assert {:ok, _} = Accounts.set_pin(barista, "4321")

      conn =
        post(conn, ~p"/session/pin", %{
          "user_id" => barista.id,
          "pin" => "9999"
        })

      assert redirected_to(conn) == ~p"/login"
      assert is_nil(get_session(conn, :user_id))
      assert shift_count(barista.id) == 0
    end

    test "inactive pin login creates no staff shift", %{conn: conn} do
      {:ok, inactive} =
        Accounts.register_user(%{
          name: "Inactive Pin",
          email: "inactive.pin.auth@test.local",
          password: "password123",
          role: "barista"
        })

      assert {:ok, _} = Accounts.set_pin(inactive, "4321")
      assert {:ok, _} = Accounts.update_user(inactive, %{active: false})

      conn =
        post(conn, ~p"/session/pin", %{
          "user_id" => inactive.id,
          "pin" => "4321"
        })

      assert redirected_to(conn) == ~p"/login"
      assert is_nil(get_session(conn, :user_id))
      assert shift_count(inactive.id) == 0
    end

    test "successful email login opens exactly one staff shift", %{conn: conn, barista: barista} do
      conn =
        post(conn, ~p"/session", %{
          "user" => %{"email" => barista.email, "password" => "password123"}
        })

      assert redirected_to(conn) == ~p"/staff"
      assert get_session(conn, :user_id) == barista.id

      open = StaffShifts.get_open_shift(barista)
      assert %StaffShift{} = open
      assert is_nil(open.ended_at)
      assert shift_count(barista.id) == 1
    end

    test "failed password login creates no staff shift", %{conn: conn, barista: barista} do
      conn =
        post(conn, ~p"/session", %{
          "user" => %{"email" => barista.email, "password" => "wrong-password"}
        })

      assert redirected_to(conn) == ~p"/login"
      assert is_nil(get_session(conn, :user_id))
      assert shift_count(barista.id) == 0
    end

    test "login with existing open shift auto-closes and opens one new shift", %{
      conn: conn,
      barista: barista
    } do
      assert {:ok, _} = Accounts.set_pin(barista, "4321")
      assert {:ok, first} = StaffShifts.open_shift_for_login(barista)

      conn =
        post(conn, ~p"/session/pin", %{
          "user_id" => barista.id,
          "pin" => "4321"
        })

      assert redirected_to(conn) == ~p"/staff"

      first = Repo.get!(StaffShift, first.id)
      assert first.end_reason == "auto_close"
      assert %DateTime{} = first.ended_at

      open = StaffShifts.get_open_shift(barista)
      assert open.id != first.id
      assert is_nil(open.ended_at)
      assert shift_count(barista.id) == 2
      assert open_shift_count(barista.id) == 1
    end

    test "explicit logout closes open staff shift", %{conn: conn, barista: barista} do
      assert {:ok, _} = Accounts.set_pin(barista, "4321")

      logged_in =
        post(conn, ~p"/session/pin", %{
          "user_id" => barista.id,
          "pin" => "4321"
        })

      assert %StaffShift{} = StaffShifts.get_open_shift(barista)

      logged_out = delete(recycle(logged_in), ~p"/logout")
      assert redirected_to(logged_out) == ~p"/login"
      assert is_nil(get_session(logged_out, :user_id))

      assert is_nil(StaffShifts.get_open_shift(barista))

      [closed] =
        StaffShift
        |> where([s], s.user_id == ^barista.id)
        |> Repo.all()

      assert closed.end_reason == "logout"
      assert %DateTime{} = closed.ended_at
    end

    test "logout with no open shift still succeeds", %{conn: conn, barista: barista} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:user_id, barista.id)

      logged_out = delete(conn, ~p"/logout")
      assert redirected_to(logged_out) == ~p"/login"
      assert is_nil(get_session(logged_out, :user_id))
      assert shift_count(barista.id) == 0
    end

    test "LiveView mount and navigation do not create another staff shift", %{
      conn: conn,
      barista: barista
    } do
      assert {:ok, _} = Accounts.set_pin(barista, "4321")

      logged_in =
        post(conn, ~p"/session/pin", %{
          "user_id" => barista.id,
          "pin" => "4321"
        })

      assert open_shift_count(barista.id) == 1
      open_before = StaffShifts.get_open_shift(barista)

      {:ok, _view, _html} = live(recycle(logged_in), ~p"/orders")
      assert open_shift_count(barista.id) == 1
      assert StaffShifts.get_open_shift(barista).id == open_before.id

      {:ok, _view, _html} = live(recycle(logged_in), ~p"/pos")
      assert open_shift_count(barista.id) == 1
      assert StaffShifts.get_open_shift(barista).id == open_before.id

      {:ok, _view, _html} = live(recycle(logged_in), ~p"/staff")
      assert open_shift_count(barista.id) == 1
      assert shift_count(barista.id) == 1
    end

    test "manager and owner login does not open a staff shift", %{
      conn: conn,
      manager: manager,
      owner: owner
    } do
      assert {:ok, _} = Accounts.set_pin(manager, "5678")
      assert {:ok, _} = Accounts.set_pin(owner, "9012")

      manager_conn =
        post(conn, ~p"/session/pin", %{
          "user_id" => manager.id,
          "pin" => "5678"
        })

      assert redirected_to(manager_conn) == ~p"/staff"
      assert get_session(manager_conn, :user_id) == manager.id
      assert shift_count(manager.id) == 0
      assert is_nil(StaffShifts.get_open_shift(manager))

      owner_conn =
        post(recycle(conn), ~p"/session", %{
          "user" => %{"email" => owner.email, "password" => "password123"}
        })

      assert redirected_to(owner_conn) == ~p"/staff"
      assert get_session(owner_conn, :user_id) == owner.id
      assert shift_count(owner.id) == 0
      assert is_nil(StaffShifts.get_open_shift(owner))
    end

    test "manager and owner logout does not create or close a staff shift", %{
      conn: conn,
      manager: manager,
      owner: owner
    } do
      for user <- [manager, owner] do
        logged_in =
          conn
          |> init_test_session(%{})
          |> put_session(:user_id, user.id)

        assert shift_count(user.id) == 0

        logged_out = delete(logged_in, ~p"/logout")
        assert redirected_to(logged_out) == ~p"/login"
        assert is_nil(get_session(logged_out, :user_id))
        assert shift_count(user.id) == 0
      end
    end
  end

  defp shift_count(user_id) do
    StaffShift
    |> where([s], s.user_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  defp open_shift_count(user_id) do
    StaffShift
    |> where([s], s.user_id == ^user_id and is_nil(s.ended_at))
    |> Repo.aggregate(:count, :id)
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end
