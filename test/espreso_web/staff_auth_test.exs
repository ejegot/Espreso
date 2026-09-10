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

  test "login lands barista on orders and managers on dashboard", %{
    conn: conn,
    barista: barista,
    manager: manager,
    owner: owner
  } do
    conn =
      post(conn, ~p"/session", %{
        "user" => %{"email" => barista.email, "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/orders"

    conn =
      post(recycle(conn), ~p"/session", %{
        "user" => %{"email" => manager.email, "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/dashboard"

    conn =
      post(recycle(conn), ~p"/session", %{
        "user" => %{"email" => owner.email, "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/dashboard"
  end

  test "anyone can open register and sign-in link is present", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/register")
    assert html =~ "Create your account"
    assert has_element?(view, "#staff-register-form")
    assert has_element?(view, "a[href='/login']", "Sign In")
    assert html =~ "Already have an account?"
  end

  test "self-register creates staff then can login", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    {:ok, conn} =
      view
      |> form("#staff-register-form", %{
        user: %{
          name: "New Staff",
          email: "newstaff@test.local",
          password: "password123",
          role: "barista"
        }
      })
      |> render_submit()
      |> follow_redirect(conn, ~p"/login")

    html = html_response(conn, 200)
    assert html =~ "Welcome back"
    assert html =~ "Account created"

    conn =
      post(recycle(conn), ~p"/session", %{
        "user" => %{"email" => "newstaff@test.local", "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/orders"
  end

  test "dashboard requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/dashboard")
  end

  test "authenticated staff can open role-aware dashboard", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/dashboard")
    assert has_element?(owner_view, ".staff-shell-title", "Dashboard")
    assert has_element?(owner_view, "#staff-nav-orders", "Orders")
    assert has_element?(owner_view, "#staff-nav-pos", "POS")
    assert has_element?(owner_view, "#staff-nav-dashboard.is-active", "Dashboard")
    assert has_element?(owner_view, "#staff-nav-availability", "Availability")
    assert has_element?(owner_view, "#staff-nav-reports", "Reports")
    assert has_element?(owner_view, "#staff-nav-staff", "Staff")
    assert has_element?(owner_view, "#staff-nav-settings", "Settings")
    assert has_element?(owner_view, "#dashboard-panel-sales", "Paid today")
    assert has_element?(owner_view, "#dashboard-paid-breakdown", "Payment methods")
    assert has_element?(owner_view, "#dashboard-panel-orders", "Orders")
    assert has_element?(owner_view, "#dashboard-panel-transactions", "Transactions")
    assert has_element?(owner_view, "#dashboard-panel-transactions[href='/transactions']")
    assert has_element?(owner_view, "#dashboard-panel-close-shift", "Close shift")
    assert has_element?(owner_view, "#dashboard-panel-close-shift[href='/staff/close']")
    assert has_element?(owner_view, "#dashboard-panel-popular-products", "Popular Products")
    assert has_element?(owner_view, "#dashboard-panel-reports", "Reports")
    refute has_element?(owner_view, "#dashboard-panel-staff-activity")
    refute render(owner_view) =~ "Coming soon"
    refute render(owner_view) =~ "86 sold-out"

    assert has_element?(owner_view, "#dashboard-panel-users.staff-home-card-owner", "Users")
    assert has_element?(owner_view, "#dashboard-panel-settings", "Settings")
    assert has_element?(owner_view, "#dashboard-panel-settings[href='/admin/settings']")
    refute has_element?(owner_view, "#dashboard-panel-settings .staff-home-soon-pill")
    assert has_element?(owner_view, "#dashboard-panel-availability", "Availability")
    assert has_element?(owner_view, "#dashboard-panel-availability[href='/admin/availability']")

    assert has_element?(
             owner_view,
             "#dashboard-panel-availability .staff-home-card-body",
             "Mark items sold out or available."
           )

    refute has_element?(owner_view, "#dashboard-panel-availability .staff-home-soon-pill")

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/dashboard")
    assert has_element?(manager_view, "#dashboard-panel-sales", "Paid today")
    assert has_element?(manager_view, "#dashboard-paid-breakdown", "Payment methods")
    assert has_element?(manager_view, "#dashboard-panel-orders", "Orders")
    assert has_element?(manager_view, "#dashboard-panel-transactions", "Transactions")
    assert has_element?(manager_view, "#dashboard-panel-transactions[href='/transactions']")
    assert has_element?(manager_view, "#dashboard-panel-close-shift", "Close shift")
    assert has_element?(manager_view, "#dashboard-panel-availability", "Availability")
    assert has_element?(manager_view, "#dashboard-panel-availability[href='/admin/availability']")

    assert has_element?(
             manager_view,
             "#dashboard-panel-availability .staff-home-card-body",
             "Mark items sold out or available."
           )

    refute has_element?(manager_view, "#dashboard-panel-availability .staff-home-soon-pill")
    refute render(manager_view) =~ "86 sold-out"

    assert has_element?(manager_view, "#dashboard-panel-reports", "Reports")
    refute has_element?(manager_view, "#dashboard-panel-users")
    refute has_element?(manager_view, "#dashboard-panel-settings")
    refute has_element?(manager_view, "#dashboard-panel-popular-products")

    {:ok, staff_view, _html} = live(log_in(conn, barista), ~p"/dashboard")
    refute has_element?(staff_view, "#staff-nav-dashboard")
    refute has_element?(staff_view, "#staff-nav-availability")
    refute has_element?(staff_view, "#staff-nav-reports")
    refute has_element?(staff_view, "#staff-nav-staff")
    refute has_element?(staff_view, "#staff-nav-settings")
    assert has_element?(staff_view, "#staff-nav-orders", "Orders")
    assert has_element?(staff_view, "#staff-nav-pos", "POS")
    refute has_element?(staff_view, "#dashboard-panel-todays-orders")
    assert has_element?(staff_view, "#dashboard-todays-orders-preview", "Today’s Orders")
    refute has_element?(staff_view, "#dashboard-panel-sales")
    refute has_element?(staff_view, "#dashboard-paid-breakdown")
    refute has_element?(staff_view, "#dashboard-panels")
    refute has_element?(staff_view, "#dashboard-panel-reports")
    refute has_element?(staff_view, "#dashboard-panel-settings")
    refute has_element?(staff_view, "#dashboard-panel-availability")
    refute has_element?(staff_view, "#dashboard-panel-transactions")
  end

  test "dashboard Orders panels show real overview counts", %{
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

    expected_orders_body = "2 active · 1 received · 1 preparing · 1 unpaid"

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/dashboard")

    assert has_element?(
             owner_view,
             "#dashboard-panel-orders .staff-home-card-body",
             expected_orders_body
           )

    assert has_element?(owner_view, "#dashboard-panel-orders[href='/orders']")

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/dashboard")

    assert has_element?(
             manager_view,
             "#dashboard-panel-orders .staff-home-card-body",
             expected_orders_body
           )

    {:ok, staff_view, _html} = live(log_in(conn, barista), ~p"/dashboard")
    refute has_element?(staff_view, "#dashboard-panel-todays-orders")
    assert has_element?(staff_view, "#dashboard-todays-orders-preview")
    assert has_element?(staff_view, "#dashboard-todays-orders-preview a[href='/orders']")
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

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/dashboard")

    assert has_element?(
             owner_view,
             "#dashboard-panel-sales .staff-home-card-body",
             expected_body
           )

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/dashboard")

    assert has_element?(
             manager_view,
             "#dashboard-panel-sales .staff-home-card-body",
             expected_body
           )

    {:ok, staff_view, _html} = live(log_in(conn, barista), ~p"/dashboard")
    refute has_element?(staff_view, "#dashboard-panel-sales")
  end

  test "dashboard Popular Products is owner-only with real or empty data", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    alias Espreso.Orders

    {:ok, owner_empty, _html} = live(log_in(conn, owner), ~p"/dashboard")

    assert has_element?(
             owner_empty,
             "#dashboard-panel-popular-products .staff-home-card-body",
             "No paid product sales today."
           )

    {:ok, manager_empty, _html} = live(log_in(conn, manager), ~p"/dashboard")
    refute has_element?(manager_empty, "#dashboard-panel-popular-products")

    {:ok, staff_empty, _html} = live(log_in(conn, barista), ~p"/dashboard")
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

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/dashboard")

    assert has_element?(owner_view, "#dashboard-panel-popular-products .dashboard-popular-list")
    assert has_element?(owner_view, "#dashboard-panel-popular-products li", "Americano")
    assert has_element?(owner_view, "#dashboard-panel-popular-products li", "Espresso")
    assert render(owner_view) =~ "Americano"
    assert render(owner_view) =~ "· 3"
    assert render(owner_view) =~ "· 1"

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/dashboard")
    refute has_element?(manager_view, "#dashboard-panel-popular-products")

    {:ok, staff_view, _html} = live(log_in(conn, barista), ~p"/dashboard")
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

    {:ok, owner_empty, _html} = live(log_in(conn, owner), ~p"/dashboard")

    assert has_element?(
             owner_empty,
             "#dashboard-panel-reports .staff-home-card-body",
             "No paid sales in the last 7 days."
           )

    {:ok, manager_empty, _html} = live(log_in(conn, manager), ~p"/dashboard")

    assert has_element?(
             manager_empty,
             "#dashboard-panel-reports .staff-home-card-body",
             "No paid sales in the last 7 days."
           )

    {:ok, staff_empty, _html} = live(log_in(conn, barista), ~p"/dashboard")
    refute has_element?(staff_empty, "#dashboard-panel-reports")

    {:ok, paid} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Report Paid", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(paid)

    expected_body = "#{Menu.format_price(Decimal.new("75"))} last 7 days · 1 paid orders"

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/dashboard")

    assert has_element?(
             owner_view,
             "#dashboard-panel-reports .staff-home-card-body",
             expected_body
           )

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/dashboard")

    assert has_element?(
             manager_view,
             "#dashboard-panel-reports .staff-home-card-body",
             expected_body
           )

    {:ok, staff_view, _html} = live(log_in(conn, barista), ~p"/dashboard")
    refute has_element?(staff_view, "#dashboard-panel-reports")
  end

  test "dashboard todays orders preview empty state for all roles", %{
    conn: conn,
    owner: owner,
    manager: manager,
    barista: barista
  } do
    for user <- [owner, manager, barista] do
      {:ok, view, _html} = live(log_in(conn, user), ~p"/dashboard")
      assert has_element?(view, "#dashboard-todays-orders-preview", "Today’s Orders")

      assert has_element?(
               view,
               "#dashboard-todays-orders-preview .staff-empty",
               "No orders yet today."
             )

      assert has_element?(
               view,
               "#dashboard-todays-orders-preview a[href='/orders']",
               "Open order queue"
             )
    end
  end

  test "dashboard todays orders preview shows real orders for all roles", %{
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
      {:ok, view, _html} = live(log_in(conn, user), ~p"/dashboard")

      assert has_element?(view, "#dashboard-todays-orders-preview")

      assert has_element?(
               view,
               "#dashboard-preview-order-#{preparing.id} .staff-order-number",
               preparing.number
             )

      assert has_element?(
               view,
               "#dashboard-preview-order-#{preparing.id} .staff-order-name",
               "Cora"
             )

      assert has_element?(
               view,
               "#dashboard-preview-order-#{preparing.id} .staff-badge--preparing",
               "Preparing"
             )

      assert has_element?(view, "#dashboard-todays-orders-preview a[href='/orders']")
      refute has_element?(view, "#dashboard-preview-order-#{preparing.id} .staff-order-items")
      refute has_element?(view, "#dashboard-preview-order-#{preparing.id} button")
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
    assert has_element?(barista_view, ".staff-home-brand", "ELIlai Kafe")
    assert has_element?(barista_view, "#staff-home-orders", "Orders")
    assert has_element?(barista_view, "#staff-home-pos", "POS")
    refute has_element?(barista_view, "#staff-home-dashboard")
    refute has_element?(barista_view, "#staff-nav-close")

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/staff")
    assert has_element?(manager_view, "#staff-home-dashboard", "Dashboard")
    assert has_element?(manager_view, "#staff-home-availability", "Availability")
    assert has_element?(manager_view, "#staff-nav-close", "Close shift")

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/staff")
    assert has_element?(owner_view, "#staff-home-staff", "Staff")
    assert has_element?(owner_view, "#staff-home-settings", "Settings")
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
    assert has_element?(view, "#staff-shell-more")
    assert has_element?(view, "#staff-nav-logout", "Log out")
    refute has_element?(view, "#staff-nav-dashboard")
    refute has_element?(view, "#staff-nav-staff")
  end

  test "manager can access staff routes but not user management", %{
    conn: conn,
    manager: manager
  } do
    conn = log_in(conn, manager)

    {:ok, orders, _html} = live(conn, ~p"/orders")
    assert has_element?(orders, ".staff-shell-title", "Orders")
    assert has_element?(orders, "#staff-nav-dashboard", "Dashboard")
    assert has_element?(orders, "#staff-nav-availability", "Availability")
    assert has_element?(orders, "#staff-nav-reports", "Reports")
    refute has_element?(orders, "#staff-nav-staff")

    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/admin/users")
  end

  test "owner can open staff admin from shell", %{conn: conn, owner: owner} do
    conn = log_in(conn, owner)
    {:ok, admin, _html} = live(conn, ~p"/admin/users")
    assert has_element?(admin, ".staff-shell-title", "Staff")
    assert has_element?(admin, "#staff-nav-staff.is-active", "Staff")
    assert has_element?(admin, "#staff-shell-more.is-active")
  end

  test "staff cannot open admin users", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    assert {:error, {:redirect, %{to: "/orders"}}} = live(conn, ~p"/admin/users")
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

  test "pin login lands barista on orders", %{conn: conn, barista: barista} do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")

    conn =
      post(conn, ~p"/session/pin", %{
        "user_id" => barista.id,
        "pin" => "4321"
      })

    assert redirected_to(conn) == ~p"/orders"
  end

  test "pin login accepts string user_id from form", %{conn: conn, barista: barista} do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")

    conn =
      post(conn, ~p"/session/pin", %{
        "user_id" => to_string(barista.id),
        "pin" => "4321"
      })

    assert redirected_to(conn) == ~p"/orders"
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
    assert html =~ "Select your name, then enter your PIN."
    assert html =~ "ELIlai Kafe"

    assert has_element?(
             view,
             "img.staff-auth-logo[src='/images/elilai-kafe/elilai-kafe-logo.jpg']"
           )

    assert has_element?(view, "#staff-pin-login")
    assert has_element?(view, "#staff-roster-search")
    assert has_element?(view, "#staff-auth-account-recovery", "Account recovery")
    assert has_element?(view, ".staff-auth-switch--quiet a[href='/register']", "Register")

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

    assert has_element?(view, "#staff-pin-form button.staff-auth-submit--shift", "Sign In")
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

  test "staff pin login selects user and enables sign in", %{conn: conn, barista: barista} do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")

    {:ok, view, _html} = live(conn, ~p"/login")

    view |> element("#staff-roster-search") |> render_change(%{"q" => ""})
    view |> element("#staff-pin-user-#{barista.id}") |> render_click()

    assert has_element?(view, "#staff-pin-selected", barista.name)
    assert has_element?(view, "#staff-pin-enter-hint", "Enter your PIN.")

    for digit <- ~w(4 3 2 1) do
      view |> element("button[phx-value-digit=\"#{digit}\"]") |> render_click()
    end

    assert has_element?(view, ".staff-pin-dot.is-filled")
    refute has_element?(view, "#staff-pin-form button.staff-auth-submit--shift[disabled]")
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

    assert redirected_to(manager_conn) == ~p"/dashboard"
    assert get_session(manager_conn, :user_id) == manager.id

    owner_conn =
      post(recycle(conn), ~p"/session/pin", %{
        "user_id" => owner.id,
        "pin" => "9012"
      })

    assert redirected_to(owner_conn) == ~p"/dashboard"
    assert get_session(owner_conn, :user_id) == owner.id
  end

  test "logout returns to unified login", %{conn: conn, barista: barista} do
    assert {:ok, _} = Accounts.set_pin(barista, "4321")

    logged_in =
      post(conn, ~p"/session/pin", %{
        "user_id" => barista.id,
        "pin" => "4321"
      })

    assert redirected_to(logged_in) == ~p"/orders"

    logged_out = delete(recycle(logged_in), ~p"/logout")
    assert redirected_to(logged_out) == ~p"/login"

    {:ok, _view, html} = live(recycle(logged_out), ~p"/login")
    assert html =~ "Welcome back"
    assert html =~ "Select your name, then enter your PIN."
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

    assert redirected_to(other) == ~p"/dashboard"
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

    assert redirected_to(ok) == ~p"/orders"

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

      assert redirected_to(conn) == ~p"/orders"
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

      assert redirected_to(conn) == ~p"/orders"
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

      assert redirected_to(conn) == ~p"/orders"

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
