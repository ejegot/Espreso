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

  test "login lands on dashboard", %{conn: conn, barista: barista} do
    {:ok, _view, html} = live(conn, ~p"/login")
    assert html =~ "Hello, welcome back"

    conn =
      post(conn, ~p"/session", %{
        "user" => %{"email" => barista.email, "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/dashboard"
    assert get_session(conn, :user_id) == barista.id
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
    assert html =~ "Hello, welcome back"
    assert html =~ "Account created"

    conn =
      post(recycle(conn), ~p"/session", %{
        "user" => %{"email" => "newstaff@test.local", "password" => "password123"}
      })

    assert redirected_to(conn) == ~p"/dashboard"
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
    assert has_element?(owner_view, ".staff-orders-title", "Dashboard")
    assert has_element?(owner_view, "#dashboard-panel-sales", "Sales")
    assert has_element?(owner_view, "#dashboard-panel-orders", "Orders")
    assert has_element?(owner_view, "#dashboard-panel-popular-products", "Popular Products")
    assert has_element?(owner_view, "#dashboard-panel-reports", "Reports")
    assert has_element?(owner_view, "#dashboard-panel-staff-activity", "Staff Activity")
    assert has_element?(owner_view, "#dashboard-panel-users", "Users")
    assert has_element?(owner_view, "#dashboard-panel-settings", "Settings")

    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/dashboard")
    assert has_element?(manager_view, "#dashboard-panel-sales", "Sales")
    assert has_element?(manager_view, "#dashboard-panel-orders", "Orders")
    assert has_element?(manager_view, "#dashboard-panel-availability", "Availability")
    assert has_element?(manager_view, "#dashboard-panel-reports", "Reports")
    refute has_element?(manager_view, "#dashboard-panel-users")
    refute has_element?(manager_view, "#dashboard-panel-settings")

    {:ok, staff_view, _html} = live(log_in(conn, barista), ~p"/dashboard")
    assert has_element?(staff_view, "#dashboard-panel-todays-orders", "Today’s Orders")
    refute has_element?(staff_view, "#dashboard-panel-sales")
    refute has_element?(staff_view, "#dashboard-panel-reports")
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

    {:ok, _} = Orders.update_status(preparing, "preparing")

    expected_orders_body = "2 active · 1 received · 1 preparing · 2 unpaid"
    expected_todays_body = "2 today · 2 active"

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

    assert has_element?(
             staff_view,
             "#dashboard-panel-todays-orders .staff-home-card-body",
             expected_todays_body
           )

    assert has_element?(staff_view, "#dashboard-panel-todays-orders[href='/orders']")
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

    assert has_element?(
             owner_view,
             "#dashboard-panel-popular-products .staff-home-card-body",
             "Americano (3), Espresso (1)"
           )

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

  test "staff workspace remains available after dashboard login destination", %{
    conn: conn,
    barista: barista
  } do
    conn = log_in(conn, barista)
    {:ok, view, _html} = live(conn, ~p"/staff")

    assert has_element?(view, ".staff-orders-title", "Home")
    assert has_element?(view, "a[href='/orders']", "Orders")
    assert has_element?(view, "a[href='/pos']", "POS")
  end

  test "staff home shows Orders and POS, not Staff accounts", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    {:ok, view, _html} = live(conn, ~p"/staff")

    assert has_element?(view, ".staff-orders-title", "Home")
    assert has_element?(view, "a[href='/orders']", "Orders")
    assert has_element?(view, "a[href='/pos']", "POS")
    refute has_element?(view, "a[href='/admin/users']", "Staff accounts")
  end

  test "manager can access staff routes but not user management", %{
    conn: conn,
    manager: manager
  } do
    conn = log_in(conn, manager)

    {:ok, home, _html} = live(conn, ~p"/staff")
    assert has_element?(home, "a[href='/orders']", "Orders")
    refute has_element?(home, "a[href='/admin/users']", "Staff accounts")

    {:ok, orders, _html} = live(conn, ~p"/orders")
    assert has_element?(orders, ".staff-orders-title")

    assert {:error, {:redirect, %{to: "/staff"}}} = live(conn, ~p"/admin/users")
  end

  test "owner staff home shows Staff accounts", %{conn: conn, owner: owner} do
    conn = log_in(conn, owner)
    {:ok, view, _html} = live(conn, ~p"/staff")
    assert has_element?(view, "a[href='/admin/users']", "Staff accounts")

    {:ok, admin, _html} = live(conn, ~p"/admin/users")
    assert has_element?(admin, ".staff-orders-title", "Staff users")
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

  test "pos placeholder is reachable for staff", %{conn: conn, barista: barista} do
    conn = log_in(conn, barista)
    {:ok, view, _html} = live(conn, ~p"/pos")
    assert has_element?(view, ".staff-orders-title", "POS")
    assert render(view) =~ "Coming soon"
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end
