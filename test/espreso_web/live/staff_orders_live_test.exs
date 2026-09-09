defmodule EspresoWeb.StaffOrdersLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Espreso.Accounts
  alias Espreso.Orders
  alias Espreso.PhysicalActionCoordinator
  alias Espreso.Printer
  alias Espreso.Repo

  setup %{conn: conn} do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Mia",
        email: "mia@test.local",
        password: "password123",
        role: "barista"
      })

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, barista.id)

    %{conn: conn, barista: barista}
  end

  test "Orders header centers ELIlai Kafe and overlays actionable counts", %{
    conn: conn,
    barista: barista
  } do
    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#staff-shell .staff-shell-bar--orders")
    assert has_element?(view, ".staff-shell-orders-title", "Orders")

    assert has_element?(
             view,
             ".staff-shell-orders-brand[src='/images/elilai-kafe/elilai-kafe-logo.jpg']"
           )

    assert has_element?(
             view,
             ".staff-shell-tools-block--orders .staff-shell-user--orders",
             "#{barista.name} · Staff"
           )

    assert has_element?(view, "#orders-new-header-link[href='#orders-new']", "New")
    assert has_element?(view, "#unpaid-drawer-toggle", "Unpaid")
    assert has_element?(view, "#staff-notif-toggle svg")
    assert has_element?(view, "#orders-refresh .staff-orders-refresh-icon")
    refute has_element?(view, "#orders-new-header-count")
    refute has_element?(view, "#orders-unpaid-header-count")

    {:ok, _order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Header Count", fulfillment: :pickup, payment_method: :counter}
      )

    _ = :sys.get_state(view.pid)

    assert has_element?(view, "#orders-new-header-count.staff-orders-tool-badge", "1")
    assert has_element?(view, "#orders-unpaid-header-count.staff-orders-tool-badge", "1")
  end

  test "new unpaid ticket shows Cash GCash Maya; Prepare waits for payment", %{
    conn: conn
  } do
    {:ok, order} =
      Orders.create_order(
        [
          %{name: "Iced Latte", size: "16oz", quantity: 2, price: Decimal.new("120")},
          %{name: "Muffin", size: nil, quantity: 1, price: Decimal.new("85")}
        ],
        %{
          customer_name: "Juan",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#order-card-new-#{order.id} .staff-order-number", order.number)
    assert has_element?(view, "#order-card-new-#{order.id} .staff-order-name", "Juan")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "2 ×")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "Iced Latte")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "16oz")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "1 ×")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "Muffin")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-pay", "₱325")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-pay", "UNPAID")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-age", "Just now")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-meta", "Takeout")

    assert has_element?(
             view,
             "#ticket-new-paid-via-cash-#{order.id}.staff-action-primary",
             "Cash"
           )

    assert has_element?(view, "#ticket-new-paid-via-gcash-#{order.id}", "GCash")
    assert has_element?(view, "#ticket-new-paid-via-maya-#{order.id}", "Maya")
    assert has_element?(view, "#cancel-order-#{order.id}", "Cancel")
    refute has_element?(view, "#ticket-new-mark-paid-#{order.id}")
    refute has_element?(view, "#order-prepare-#{order.id}")
    refute has_element?(view, "#order-ready-#{order.id}")
    refute has_element?(view, "#order-card-new-#{order.id} .staff-badge--received")
    refute has_element?(view, "#orders-new-workload")
  end

  test "Cash opens tender modal and exact confirmation moves the paid order to Preparing", %{
    conn: conn
  } do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Mia",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_intent: :cash
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    refute has_element?(view, "#order-prepare-#{order.id}")
    assert has_element?(view, "#ticket-new-paid-via-cash-#{order.id}", "Cash")
    refute has_element?(view, "#ticket-new-paid-via-gcash-#{order.id}")
    refute has_element?(view, "#ticket-new-paid-via-maya-#{order.id}")

    view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()

    assert has_element?(view, "#orders-cash-tender-modal", "Cash Received")
    assert has_element?(view, "#orders-cash-total", "₱75")
    assert has_element?(view, "#orders-cash-exact[data-dismiss-keyboard]")
    assert has_element?(view, "#orders-cash-preset-100[data-dismiss-keyboard]")
    assert has_element?(view, "#orders-confirm-cash[disabled][data-dismiss-keyboard]")

    unchanged = Orders.get_order_by_number!(order.number)
    assert unchanged.payment_status == "unpaid"
    assert unchanged.paid_via == nil

    confirm_cash_exact(view)

    refute has_element?(view, "#orders-cash-tender-modal")
    assert has_element?(view, "#orders-preparing #order-card-preparing-#{order.id}")
    assert has_element?(view, "#order-ready-#{order.id}.staff-action-primary", "Ready")

    assert has_element?(
             view,
             "#{detail_id(order.id, "preparing")} .staff-order-items",
             "Espresso"
           )

    assert has_element?(view, "#{detail_id(order.id, "preparing")} .staff-order-meta", "Takeout")
  end

  test "legacy counter Cash opens the same modal while wallet actions remain direct", %{
    conn: conn
  } do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Legacy Cash", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()

    assert has_element?(view, "#orders-cash-tender-modal", order.number)
    assert live_assigns(view).cash_tender_order.id == order.id
    assert Repo.get!(Espreso.Orders.Order, order.id).payment_status == "unpaid"
  end

  test "Cash tender validates invalid and insufficient amounts without settling", %{conn: conn} do
    order = cash_intent_order!("Cash Validation", "150")
    {:ok, view, _html} = live(conn, ~p"/orders")
    view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()
    token = live_assigns(view).cash_tender_token

    view
    |> render_submit("confirm_order_cash_tender", %{
      "cash_tender_token" => "stale-token",
      "cash_tendered" => "150"
    })

    assert has_element?(view, "#orders-cash-tender-feedback", "no longer active")
    assert Repo.get!(Espreso.Orders.Order, order.id).payment_status == "unpaid"

    for amount <- ["", "0", "-1", "abc", "150.001"] do
      view
      |> form("#orders-cash-tender-form", %{
        "cash_tender_token" => token,
        "cash_tendered" => amount
      })
      |> render_submit()

      assert Repo.get!(Espreso.Orders.Order, order.id).payment_status == "unpaid"
      assert has_element?(view, "#orders-cash-tender-modal")
      assert has_element?(view, "#orders-confirm-cash[disabled]")
    end

    view
    |> form("#orders-cash-tender-form", %{
      "cash_tender_token" => token,
      "cash_tendered" => "100"
    })
    |> render_change()

    assert has_element?(view, "#orders-cash-tender-feedback.is-short", "Still needed")
    assert has_element?(view, "#orders-cash-tender-feedback", "₱50")
    assert has_element?(view, "#orders-confirm-cash[disabled]")

    view
    |> form("#orders-cash-tender-form", %{
      "cash_tender_token" => token,
      "cash_tendered" => ".50"
    })
    |> render_change()

    assert has_element?(view, "#orders-cash-tender-feedback.is-short", "Still needed")
  end

  test "Cash tender accepts practical formats and calculates exact and overpayment change", %{
    conn: conn
  } do
    order = cash_intent_order!("Cash Formats", "150")
    {:ok, view, _html} = live(conn, ~p"/orders")
    view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()
    token = live_assigns(view).cash_tender_token

    for amount <- ["150", "150.0", "150.00", "1,000.00"] do
      view
      |> form("#orders-cash-tender-form", %{
        "cash_tender_token" => token,
        "cash_tendered" => amount
      })
      |> render_change()

      refute has_element?(view, "#orders-confirm-cash[disabled]")
    end

    view
    |> form("#orders-cash-tender-form", %{
      "cash_tender_token" => token,
      "cash_tendered" => "150"
    })
    |> render_change()

    assert has_element?(view, "#orders-cash-tender-feedback", "Exact")
    assert has_element?(view, "#orders-cash-tender-feedback", "₱0")

    view |> element("#orders-cash-preset-200") |> render_click()
    assert has_element?(view, ~s(#orders-cash-tendered[value="200.00"]))
    assert has_element?(view, "#orders-cash-tender-feedback", "Change")
    assert has_element?(view, "#orders-cash-tender-feedback", "₱50")
    refute has_element?(view, "#orders-cash-preset-100")
    assert has_element?(view, "#orders-cash-preset-500")
    assert has_element?(view, "#orders-cash-preset-1000")
  end

  test "Cash overpayment settles as cash through the existing action", %{
    conn: conn,
    barista: barista
  } do
    order = cash_intent_order!("Cash Change", "150")
    {:ok, view, _html} = live(conn, ~p"/orders")
    view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()
    token = live_assigns(view).cash_tender_token

    view
    |> form("#orders-cash-tender-form", %{
      "cash_tender_token" => token,
      "cash_tendered" => "200"
    })
    |> render_submit()

    paid = Repo.get!(Espreso.Orders.Order, order.id)
    assert paid.payment_status == "paid"
    assert paid.paid_via == "cash"
    assert paid.status == "preparing"
    assert %DateTime{} = paid.settled_at
    assert paid.settled_by_user_id == barista.id
    assert paid.settlement_source == "staff_orders"
    assert paid.settlement_time_estimated == false
    assert Decimal.equal?(paid.cash_tendered, Decimal.new("200"))
    assert Decimal.equal?(paid.change_due, Decimal.new("50"))
    refute has_element?(view, "#orders-cash-tender-modal")
  end

  test "cancelling Cash tender clears modal state without consuming its permit", %{conn: conn} do
    order = cash_intent_order!("Cash Cancel", "150")
    {:ok, view, _html} = live(conn, ~p"/orders")
    permit = live_assigns(view).mark_paid_permits[order.id]
    view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()
    view |> element("#orders-cash-preset-200") |> render_click()
    view |> element("#orders-cancel-cash") |> render_click()

    refute has_element?(view, "#orders-cash-tender-modal")
    assert live_assigns(view).cash_tender_order == nil
    assert live_assigns(view).cash_tendered == ""
    assert Repo.get!(Espreso.Orders.Order, order.id).payment_status == "unpaid"

    assert PhysicalActionCoordinator.permits(:mark_paid, [order.id]) == %{
             order.id => permit
           }
  end

  test "stale Cash modal rejects an order paid elsewhere and repeated confirmation is inert", %{
    conn: conn
  } do
    order = cash_intent_order!("Stale Cash", "150")
    {:ok, view, _html} = live(conn, ~p"/orders")
    view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()
    token = live_assigns(view).cash_tender_token

    assert {:ok, paid} = Orders.mark_paid(order, paid_via: "cash")
    _ = :sys.get_state(view.pid)

    params = %{"cash_tender_token" => token, "cash_tendered" => "200"}
    view |> render_submit("confirm_order_cash_tender", params)
    view |> render_submit("confirm_order_cash_tender", params)

    assert Repo.get!(Espreso.Orders.Order, order.id).payment_status == "paid"
    assert Repo.get!(Espreso.Orders.Order, order.id).updated_at == paid.updated_at
    refute has_element?(view, "#orders-cash-tender-modal")
    assert has_element?(view, "#orders-flash", "Could not mark order paid.")
  end

  test "Cash modal refreshes a rotated permit before opening", %{conn: conn} do
    order = cash_intent_order!("Rotated Cash", "150")
    {:ok, view, _html} = live(conn, ~p"/orders")
    stale_permit = live_assigns(view).mark_paid_permits[order.id]

    assert {:ineligible, {:payment_intent_mismatch, "cash", "gcash"}} =
             PhysicalActionCoordinator.execute_mark_paid(order.id, stale_permit, "gcash")

    fresh_permit =
      PhysicalActionCoordinator.permits(:mark_paid, [order.id])
      |> Map.fetch!(order.id)

    refute fresh_permit == stale_permit
    view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()

    assert has_element?(view, "#orders-cash-tender-modal")
    assert live_assigns(view).mark_paid_permits[order.id] == fresh_permit
    assert Repo.get!(Espreso.Orders.Order, order.id).payment_status == "unpaid"
  end

  test "rejected payment choice refreshes the permit for a valid retry", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Cash Intent",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_intent: :cash
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#ticket-new-paid-via-cash-#{order.id}")
    refute has_element?(view, "#ticket-new-paid-via-gcash-#{order.id}")
    refute has_element?(view, "#ticket-new-paid-via-maya-#{order.id}")

    rejected_permit =
      PhysicalActionCoordinator.permits(:mark_paid, [order.id])
      |> Map.fetch!(order.id)

    render_click(view, "mark_paid", %{
      "id" => Integer.to_string(order.id),
      "action" => "mark_paid",
      "permit" => rejected_permit,
      "paid_via" => "gcash"
    })

    rejected = Orders.get_order_by_number!(order.number)
    assert rejected.payment_status == "unpaid"
    assert rejected.paid_via == nil
    assert has_element?(view, "#orders-flash", "Could not mark order paid.")

    mark_paid_via(view, order, "cash", "ticket", "new")

    paid = Orders.get_order_by_number!(order.number)
    assert paid.payment_status == "paid"
    assert paid.paid_via == "cash"
    assert has_element?(view, "#orders-preparing #order-card-preparing-#{order.id}")
  end

  test "Ready ticket shows items and Picked up as primary action", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Spanish Latte", size: "Regular", quantity: 1, price: Decimal.new("150")}],
        %{
          customer_name: "Ready Guest",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, _} = Orders.mark_paid(order, paid_via: "cash")

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#orders-preparing #order-card-preparing-#{order.id}")
    view |> element("#order-ready-#{order.id}", "Ready") |> render_click()

    assert has_element?(view, "#orders-ready #order-card-ready-#{order.id}")

    assert has_element?(
             view,
             "#{detail_id(order.id, "ready")} .staff-order-items",
             "Spanish Latte"
           )

    assert has_element?(view, "#{detail_id(order.id, "ready")} .staff-order-pay", "PAID")
    assert has_element?(view, "#{detail_id(order.id, "ready")} .staff-order-pay-via", "CASH")
    assert has_element?(view, "#ready-complete-#{order.id}.staff-action-primary", "Picked up")
    refute has_element?(view, "#ticket-ready-mark-paid-#{order.id}")
    refute has_element?(view, "#order-card-ready-#{order.id}.staff-order-card-muted")
  end

  test "kitchen workspace groups New Preparing Ready; Unpaid stays in collections", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Board Geometry",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#orders-kitchen[aria-label='Kitchen']")
    assert has_element?(view, "#orders-kitchen #orders-new")
    assert has_element?(view, "#orders-kitchen #orders-preparing")
    assert has_element?(view, "#orders-kitchen #orders-ready")
    assert has_element?(view, "#orders-kitchen .staff-orders-kds-lane--new")
    assert has_element?(view, "#orders-kitchen .staff-orders-kds-lane--preparing")
    assert has_element?(view, "#orders-kitchen .staff-orders-kds-lane--ready")
    assert has_element?(view, "#orders-new .staff-orders-kds-head h2", "New")
    assert has_element?(view, "#orders-kitchen #order-card-new-#{order.id}")
    assert has_element?(view, detail_id(order.id))

    assert has_element?(view, "#unpaid-orders[aria-label='Unpaid orders']")
    assert has_element?(view, ".staff-orders-collections#unpaid-orders")
    refute has_element?(view, "#orders-kitchen #unpaid-orders")
    assert has_element?(view, "#unpaid-order-#{order.id}")
    assert has_element?(view, "#unpaid-drawer-toggle")
  end

  test "New lane distinguishes staff-actionable and online-waiting orders", %{conn: conn} do
    {:ok, actionable} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "At Counter", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, waiting} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("120")}],
        %{customer_name: "Online Guest", fulfillment: :pickup, payment_method: :online}
      )

    {:ok, waiting} = Orders.attach_paymongo_session(waiting, "cs_pass3_workload")

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#orders-new .staff-orders-count", "2")
    assert has_element?(view, "#orders-new-workload", "1 need staff")
    assert has_element?(view, "#orders-new-workload", "1 waiting online")
    assert has_element?(view, "#ticket-new-paid-via-cash-#{actionable.id}", "Cash")

    assert has_element?(
             view,
             "#order-card-new-#{waiting.id} .staff-order-payment-waiting",
             "Waiting for online payment"
           )

    assert has_element?(view, ~s(.staff-orders-lane-jump[href="#orders-new"]), "New 2")

    assert has_element?(
             view,
             ~s(.staff-orders-lane-jump[href="#orders-preparing"]),
             "Preparing 0"
           )

    assert has_element?(view, ~s(.staff-orders-lane-jump[href="#orders-ready"]), "Ready 0")
  end

  test "cancel action voids unpaid active order and removes it from active list", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Cancel Me",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")
    assert has_element?(view, "#cancel-order-#{order.id}", "Cancel")

    view |> element("#cancel-order-#{order.id}") |> render_click()

    assert has_element?(view, "#orders-flash", "#{order.number} cancelled.")
    refute has_element?(view, ".staff-order-number", order.number)
    refute has_element?(view, "#ticket-new-paid-via-cash-#{order.id}")
    refute has_element?(view, "#ticket-new-paid-via-gcash-#{order.id}")
    refute has_element?(view, "#ticket-new-paid-via-maya-#{order.id}")
    assert Orders.list_active_orders() == []
  end

  test "cancel is blocked when online checkout session is attached", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Paying Online",
          fulfillment: :pickup,
          payment_method: :online
        }
      )

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_staff_cancel")

    {:ok, view, _html} = live(conn, ~p"/orders")
    refute has_element?(view, "#cancel-order-#{order.id}")
    assert has_element?(view, "#abandon-online-payment-#{order.id}", "Abandon")

    assert {:error, :checkout_in_progress} = Orders.cancel_order(order)

    order = Espreso.Repo.get!(Espreso.Orders.Order, order.id)
    assert order.status == "received"
    assert order.paymongo_checkout_session_id == "cs_staff_cancel"
    assert Enum.any?(Orders.list_active_orders(), &(&1.id == order.id))
  end

  test "abandon payment closes unpaid online checkout and removes ticket", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Abandoned Pay",
          fulfillment: :pickup,
          payment_method: :online
        }
      )

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_staff_abandon")

    {:ok, view, _html} = live(conn, ~p"/orders")
    assert has_element?(view, "#abandon-online-payment-#{order.id}", "Abandon")

    view |> element("#abandon-online-payment-#{order.id}") |> render_click()

    assert has_element?(view, "#orders-flash", "#{order.number} online payment abandoned.")
    refute has_element?(view, ".staff-order-number", order.number)

    order = Espreso.Repo.get!(Espreso.Orders.Order, order.id)
    assert order.status == "cancelled"
    assert order.payment_status == "unpaid"
    assert order.paymongo_checkout_session_id == "cs_staff_abandon"
    assert Orders.list_active_orders() == []
  end

  test "reconciliation drawer shows captured PayMongo payments for cancelled orders", %{
    conn: conn
  } do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}],
        %{
          customer_name: "Recon UI",
          fulfillment: :pickup,
          payment_method: :online
        }
      )

    assert {:ok, _record} =
             Orders.record_paymongo_reconciliation(%{
               order_id: order.id,
               order_number: order.number,
               paymongo_checkout_session_id: "cs_staff_recon_ui",
               paymongo_payment_id: "pay_staff_recon",
               paymongo_webhook_event_id: "evt_staff_recon",
               amount_centavos: 10_000,
               currency: "PHP"
             })

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#reconciliation-drawer-toggle", "Reconciliation")
    assert has_element?(view, ".staff-orders-reconciliation-toggle-count", "1")

    view |> element("#reconciliation-drawer-toggle") |> render_click()

    assert has_element?(view, "#paymongo-reconciliations")
    assert has_element?(view, "#paymongo-reconciliations", order.number)
    assert has_element?(view, "#paymongo-reconciliations", "₱100")
    assert has_element?(view, "#paymongo-reconciliations", "cs_staff_rec…")

    assert has_element?(
             view,
             "#paymongo-reconciliations",
             "Payment captured at PayMongo — order cancelled locally"
           )
  end

  test "reconciliation drawer is empty when there are no records", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/orders")

    refute has_element?(view, "#reconciliation-drawer-toggle")
  end

  test "unpaid online ticket cannot prepare until paid; shows Abandon", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}],
        %{
          customer_name: "Online Gate",
          fulfillment: :pickup,
          payment_method: :online
        }
      )

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_staff_online_gate")

    {:ok, view, _html} = live(conn, ~p"/orders")

    refute has_element?(view, "#order-prepare-#{order.id}")
    refute has_element?(view, "#ticket-new-mark-paid-#{order.id}")
    refute has_element?(view, "#order-card-new-#{order.id} button", "Cash")

    assert has_element?(
             view,
             "#order-card-new-#{order.id} .staff-order-payment-waiting",
             "Waiting for online payment"
           )

    assert has_element?(view, "#abandon-online-payment-#{order.id}", "Abandon")

    assert {:error, :payment_required} = Orders.update_status(order, "preparing")

    reloaded = Orders.get_order_by_number!(order.number)
    assert reloaded.status == "received"
    assert reloaded.payment_status == "unpaid"
  end

  test "PayMongo GCash and Maya intents wait for webhook settlement without manual actions", %{
    conn: conn
  } do
    set_payments_mode!("paymongo")

    orders =
      for wallet <- [:gcash, :maya] do
        {:ok, order} =
          Orders.create_order(
            [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}],
            %{
              customer_name: "#{wallet} PayMongo",
              fulfillment: :pickup,
              payment_method: :online,
              payment_intent: wallet
            }
          )

        {:ok, order} =
          Orders.attach_paymongo_session(order, "cs_staff_#{wallet}_intent")

        order
      end

    {:ok, view, _html} = live(conn, ~p"/orders")

    for order <- orders do
      assert has_element?(
               view,
               "#order-card-new-#{order.id} .staff-order-payment-waiting",
               "Waiting for online payment"
             )

      refute has_element?(view, "#ticket-new-mark-paid-#{order.id}")
      refute has_element?(view, "#ticket-new-paid-via-cash-#{order.id}")
      refute has_element?(view, "#ticket-new-paid-via-gcash-#{order.id}")
      refute has_element?(view, "#ticket-new-paid-via-maya-#{order.id}")
    end
  end

  test "online paid ticket can ready and be picked up", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}],
        %{
          customer_name: "Online Paid Gate",
          fulfillment: :pickup,
          payment_method: :online
        }
      )

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_staff_online_paid")
    assert {:ok, _} = Orders.mark_paid_from_paymongo(order.number)

    {:ok, view, _html} = live(conn, ~p"/orders")

    # PayMongo paid auto-advances New → Preparing
    assert has_element?(view, "#order-ready-#{order.id}", "Ready")
    refute has_element?(view, "#order-prepare-#{order.id}")
    refute has_element?(view, "#order-card-new-#{order.id} button", "Cash")
    refute has_element?(view, "#ticket-preparing-mark-paid-#{order.id}")
    refute has_element?(view, "#ticket-preparing-paid-via-gcash-#{order.id}")
    refute has_element?(view, "#ticket-preparing-paid-via-maya-#{order.id}")

    view |> element("#order-ready-#{order.id}") |> render_click()
    assert has_element?(view, "#ready-complete-#{order.id}", "Picked up")

    view |> element("#ready-complete-#{order.id}") |> render_click()
    assert has_element?(view, "#orders-flash", "#{order.number} picked up.")
    refute has_element?(view, "#orders-ready .staff-order-number", order.number)
  end

  test "cancel is unavailable for paid orders; mark paid still works", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Paid Keep",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")
    assert has_element?(view, "#cancel-order-#{order.id}")
    assert has_element?(view, "#unpaid-drawer-paid-via-cash-#{order.id}")

    mark_paid_via(view, order, "cash", "unpaid", "drawer")

    refute has_element?(view, "#cancel-order-#{order.id}")
    refute has_element?(view, "#unpaid-order-#{order.id}")
    assert has_element?(view, "#{detail_id(order.id, "preparing")} .staff-order-pay", "PAID")
  end

  test "cancel is unavailable after order is ready", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Ready Keep",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, _} = Orders.mark_paid(order, paid_via: "cash")
    {:ok, view, _html} = live(conn, ~p"/orders")

    view |> element("#order-ready-#{order.id}") |> render_click()

    refute has_element?(view, "#cancel-order-#{order.id}")
    assert has_element?(view, "#orders-ready .staff-order-number", order.number)
  end

  test "confirm payment from New moves order to Preparing", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Auto Prep",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    mark_paid_via(view, order, "gcash", "ticket", "new")

    assert has_element?(view, "#orders-flash", "#{order.number} marked paid (GCash) · Preparing.")
    assert has_element?(view, "#orders-preparing .staff-order-number", order.number)
    assert has_element?(view, "#order-ready-#{order.id}", "Ready")

    reloaded = Orders.get_order_by_number!(order.number)
    assert reloaded.payment_status == "paid"
    assert reloaded.status == "preparing"
    assert reloaded.paid_via == "gcash"
  end

  test "ready paid order does not show Mark paid", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Ready Paid",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, _} = Orders.mark_paid(order)
    {:ok, _} = Orders.update_status(order, "ready")

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, ".staff-order-number", order.number)
    refute has_element?(view, "#ticket-ready-mark-paid-#{order.id}")
    assert has_element?(view, "#ready-complete-#{order.id}", "Picked up")
  end

  test "ready order can be marked picked up and leaves Ready lane", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Pickup Me",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, _} = Orders.mark_paid(order, paid_via: "cash")
    {:ok, view, _html} = live(conn, ~p"/orders")

    view |> element("#order-ready-#{order.id}") |> render_click()

    refute has_element?(view, "#ticket-ready-mark-paid-#{order.id}")
    assert has_element?(view, "#ready-complete-#{order.id}", "Picked up")
    refute has_element?(view, "#cancel-order-#{order.id}")

    view |> element("#ready-complete-#{order.id}") |> render_click()

    assert has_element?(view, "#orders-flash", "#{order.number} picked up.")
    refute has_element?(view, "#ready-complete-#{order.id}")
    refute has_element?(view, "#orders-ready .staff-order-number", order.number)
    refute has_element?(view, "#unpaid-order-#{order.id}")

    reloaded = Orders.get_order_by_number!(order.number)
    assert reloaded.status == "completed"
    assert reloaded.payment_status == "paid"
  end

  test "board reloads when an order is completed via PubSub", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Complete Live",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, _} = Orders.mark_paid(order, paid_via: "cash")
    {:ok, _} = Orders.update_status(order, "ready")
    {:ok, view, _html} = live(conn, ~p"/orders")
    assert has_element?(view, "#ready-complete-#{order.id}")

    assert {:ok, _} = Orders.complete_order(order)
    _html = render(view)
    refute has_element?(view, "#ready-complete-#{order.id}")
    refute has_element?(view, "#unpaid-order-#{order.id}")
    refute has_element?(view, "#orders-ready .staff-order-number", order.number)
  end

  test "board reloads from PubSub without clicking Refresh", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/orders")
    assert has_element?(view, "#orders-new .staff-empty", "No new orders.")
    assert has_element?(view, "#orders-preparing .staff-empty", "Nothing preparing.")

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Live Queue",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    assert render(view) =~ order.number
    assert has_element?(view, ".staff-order-number", order.number)
    assert has_element?(view, ".staff-order-name", "Live Queue")

    assert {:ok, _} = Orders.mark_paid(order, paid_via: "cash")
    assert {:ok, _} = Orders.update_status(order, "ready")
    html = render(view)
    assert html =~ "No new orders."
    assert html =~ "Nothing preparing."
    assert has_element?(view, "#orders-ready .staff-order-number", order.number)
    assert has_element?(view, "#{detail_id(order.id, "ready")} .staff-order-items", "Espresso")
  end

  test "manual Refresh still reloads the board", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Refresh Keep",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")
    assert has_element?(view, ".staff-order-number", order.number)

    view |> element("button#orders-refresh") |> render_click()

    assert has_element?(view, ".staff-order-number", order.number)
    assert has_element?(view, ".staff-order-name", "Refresh Keep")
  end

  test "Unpaid Orders section lists today's unpaid and Mark paid removes it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/orders")
    assert has_element?(view, "#unpaid-orders-empty", "No unpaid orders today.")

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Unpaid Visible",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    # Historical unpaid completed (staff flow blocks unpaid → ready now).
    Espreso.Repo.update_all(
      from(o in Espreso.Orders.Order, where: o.id == ^order.id),
      set: [status: "completed"]
    )

    html = render(view)
    assert html =~ "Unpaid Today"
    assert has_element?(view, "#unpaid-order-#{order.id}")
    assert has_element?(view, "#unpaid-order-#{order.id} .staff-order-number", order.number)
    assert has_element?(view, "#unpaid-order-#{order.id} .staff-order-name", "Unpaid Visible")
    assert has_element?(view, "#unpaid-order-#{order.id} .staff-badge--completed", "Picked up")
    assert has_element?(view, "#unpaid-order-#{order.id} .staff-badge--pay-unpaid", "UNPAID")
    assert has_element?(view, "#unpaid-order-#{order.id} .staff-order-pay", "₱75")
    assert has_element?(view, "#unpaid-drawer-paid-via-cash-#{order.id}", "Cash")
    assert has_element?(view, "#unpaid-drawer-paid-via-gcash-#{order.id}", "GCash")
    assert has_element?(view, "#unpaid-drawer-paid-via-maya-#{order.id}", "Maya")
    refute has_element?(view, "#unpaid-orders-empty")

    mark_paid_via(view, order, "cash", "unpaid", "drawer")

    assert has_element?(view, "#orders-flash", "#{order.number} marked paid (cash).")
    refute has_element?(view, "#unpaid-order-#{order.id}")
    assert has_element?(view, "#unpaid-orders-empty", "No unpaid orders today.")
  end

  test "kitchen tickets show order age from inserted_at across lanes", %{conn: conn} do
    {:ok, fresh} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Fresh Age",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, preparing} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("120")}],
        %{
          customer_name: "Prep Age",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, ready} =
      Orders.create_order(
        [%{name: "Mocha", size: nil, quantity: 1, price: Decimal.new("140")}],
        %{
          customer_name: "Ready Age",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    backdate_order!(preparing, minutes_ago: 5)
    backdate_order!(ready, minutes_ago: 10)
    {:ok, _} = Orders.mark_paid(preparing, paid_via: "cash")
    {:ok, _} = Orders.mark_paid(ready, paid_via: "cash")
    {:ok, _} = Orders.update_status(ready, "ready")

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(
             view,
             "#orders-new #order-card-new-#{fresh.id} .staff-order-age",
             "Just now"
           )

    refute has_element?(
             view,
             "#orders-new #order-card-new-#{fresh.id} .staff-order-age--attention"
           )

    assert has_element?(
             view,
             "#orders-preparing #order-card-preparing-#{preparing.id} .staff-order-age--attention",
             "5 min ago"
           )

    assert has_element?(
             view,
             "#orders-ready #order-card-ready-#{ready.id} .staff-order-age--urgent",
             "10 min ago"
           )

    assert has_element?(
             view,
             "#ticket-new-paid-via-cash-#{fresh.id}.staff-action-primary",
             "Cash"
           )

    refute has_element?(view, "#order-prepare-#{fresh.id}")
    assert has_element?(view, "#order-ready-#{preparing.id}.staff-action-primary", "Ready")
    assert has_element?(view, "#ready-complete-#{ready.id}.staff-action-primary", "Picked up")

    reloaded = Orders.get_order_by_number!(fresh.number)
    assert reloaded.status == "received"
  end

  test "age presentation advances on a tick without reloading orders", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Tick Age", fulfillment: :pickup, payment_method: :counter}
      )

    backdate_order!(order, seconds_ago: 59)
    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#order-card-new-#{order.id} .staff-order-age", "Just now")

    Process.sleep(1_100)
    send(view.pid, :age_tick)

    assert has_element?(view, "#order-card-new-#{order.id} .staff-order-age", "1 min ago")
  end

  test "15+ minute order age uses critical emphasis without changing status", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Stale Age",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    backdate_order!(order, minutes_ago: 16)
    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(
             view,
             "#order-card-new-#{order.id} .staff-order-age--critical",
             "16 min ago"
           )

    assert has_element?(
             view,
             "#ticket-new-paid-via-cash-#{order.id}.staff-action-primary",
             "Cash"
           )

    refute has_element?(view, "#order-prepare-#{order.id}")
    assert Orders.get_order_by_number!(order.number).status == "received"
  end

  test "customer source shows QR badge; pos source shows WALK-IN badge", %{conn: conn} do
    alias Espreso.Menu.{Category, Product, ProductPrice}
    alias Espreso.Repo

    {:ok, qr_order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "QR Guest",
          fulfillment: :pickup,
          payment_method: :counter,
          source: :customer
        }
      )

    category =
      %Category{}
      |> Category.changeset(%{name: "HOT"})
      |> Repo.insert!()

    product =
      %Product{}
      |> Product.changeset(%{
        name: "Americano",
        category_id: category.id,
        available: true
      })
      |> Repo.insert!()

    price =
      %ProductPrice{}
      |> ProductPrice.changeset(%{
        product_id: product.id,
        size: "8oz",
        price: Decimal.new("110")
      })
      |> Repo.insert!()

    {:ok, pos_order} =
      Orders.create_order(
        [
          %{
            product_id: product.id,
            price_id: price.id,
            name: product.name,
            size: price.size,
            quantity: 1,
            price: price.price
          }
        ],
        %{
          customer_name: "Walk-in",
          fulfillment: :pickup,
          payment_method: :counter,
          source: :pos
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(
             view,
             "#order-source-new-#{qr_order.id}.staff-order-source--customer",
             "QR"
           )

    assert has_element?(
             view,
             "#order-source-new-#{pos_order.id}.staff-order-source--pos",
             "WALK-IN"
           )

    assert has_element?(view, "#order-card-new-#{qr_order.id} .staff-order-name", "QR Guest")
    refute has_element?(view, "#order-card-new-#{pos_order.id} .staff-order-name")
  end

  test "order notes render in a prominent NOTE block before primary action", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Café Latte", size: "12oz", quantity: 1, price: Decimal.new("140")}],
        %{
          customer_name: "Note Guest",
          fulfillment: :dine_in,
          table_number: "5",
          payment_method: :counter,
          notes: "Less sugar"
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#{detail_id(order.id)} .staff-order-note-label", "NOTE")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-notes", "Less sugar")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-meta", "Dine-in")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "12oz")

    assert has_element?(
             view,
             "#ticket-new-paid-via-cash-#{order.id}.staff-action-primary",
             "Cash"
           )

    refute has_element?(view, "#order-prepare-#{order.id}")
  end

  test "Ready lane keeps more than 10 ready orders visible", %{conn: conn} do
    ready_orders =
      for i <- 1..11 do
        {:ok, order} =
          Orders.create_order(
            [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
            %{
              customer_name: "Ready #{i}",
              fulfillment: :pickup,
              payment_method: :counter,
              payment_status: :paid
            }
          )

        {:ok, _} = Orders.update_status(order, "preparing")
        {:ok, ready} = Orders.update_status(order, "ready")
        ready
      end

    oldest = List.first(ready_orders)
    newest = List.last(ready_orders)

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#orders-ready #order-card-ready-#{oldest.id}")
    assert has_element?(view, "#orders-ready #order-card-ready-#{newest.id}")

    assert has_element?(view, "#ready-complete-#{oldest.id}", "Picked up")
    assert has_element?(view, "#orders-ready .staff-orders-count", "11")
  end

  test "unpaid order blocks Prepare and Ready until payment is confirmed", %{
    conn: conn
  } do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Spanish Latte", size: nil, quantity: 1, price: Decimal.new("150")}],
        %{
          customer_name: "Handoff Guest",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")
    refute has_element?(view, "#order-prepare-#{order.id}")
    assert has_element?(view, "#ticket-new-paid-via-cash-#{order.id}", "Cash")

    mark_paid_via(view, order, "cash", "ticket", "new")

    assert has_element?(view, "#orders-preparing #order-card-preparing-#{order.id}")
    assert has_element?(view, "#order-ready-#{order.id}.staff-action-primary", "Ready")
    view |> element("#order-ready-#{order.id}") |> render_click()
    assert has_element?(view, "#ready-complete-#{order.id}", "Picked up")
  end

  test "stage tickets are self-contained with actions on the card", %{conn: conn} do
    {:ok, first} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "First", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, second} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("120")}],
        %{customer_name: "Second", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, detail_id(first.id))
    assert has_element?(view, detail_id(second.id))
    assert has_element?(view, "#{detail_id(first.id)} .staff-order-items", "Espresso")
    assert has_element?(view, "#{detail_id(second.id)} .staff-order-items", "Latte")
    assert has_element?(view, "#ticket-new-paid-via-cash-#{first.id}", "Cash")
    assert has_element?(view, "#ticket-new-paid-via-cash-#{second.id}", "Cash")
    refute has_element?(view, "#order-prepare-#{first.id}")
    refute has_element?(view, "#order-prepare-#{second.id}")
    refute has_element?(view, ".staff-order-queue-ticket--selected")
  end

  test "empty rails show when no kitchen orders exist", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#orders-new .staff-empty", "No new orders.")
    assert has_element?(view, "#orders-preparing .staff-empty", "Nothing preparing.")
    assert has_element?(view, "#orders-ready .staff-empty", "None yet.")
  end

  test "unpaid drawer opens from header toggle", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Drawer Guest",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    refute render(view) =~ "staff-orders-unpaid-drawer--open"

    view |> element("#unpaid-drawer-toggle") |> render_click()

    assert render(view) =~ "staff-orders-unpaid-drawer--open"
    assert has_element?(view, "#unpaid-order-#{order.id}")
  end

  test "qrph awaiting_payment order shows AWAITING PAYMENT and staff can confirm with GCash", %{
    conn: conn
  } do
    set_payments_mode!("qrph_manual")

    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("120")}],
        %{
          customer_name: "QR Guest",
          fulfillment: :pickup,
          payment_method: :online,
          payment_intent: :gcash
        }
      )

    assert order.payment_status == "awaiting_payment"

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#{detail_id(order.id)} .staff-order-pay", "AWAITING PAYMENT")
    assert has_element?(view, "#ticket-new-mark-paid-#{order.id}", "Confirm payment")
    refute has_element?(view, "#ticket-new-paid-via-cash-#{order.id}")
    refute has_element?(view, "#abandon-online-payment-#{order.id}")

    view |> element("#ticket-new-mark-paid-#{order.id}") |> render_click()

    assert has_element?(view, "#mark-paid-modal-gcash.is-suggested", "GCash")
    refute has_element?(view, "#mark-paid-modal-maya")
    refute has_element?(view, "#mark-paid-modal-cash")
    refute has_element?(view, "#mark-paid-modal-counter")

    view |> element("#mark-paid-modal-gcash") |> render_click()

    assert has_element?(view, "#orders-flash", "#{order.number} marked paid (GCash) · Preparing.")

    reloaded = Orders.get_order_by_number!(order.number)
    assert reloaded.payment_status == "paid"
    assert reloaded.paid_via == "gcash"
    assert reloaded.status == "preparing"
  end

  test "qrph Maya intent confirms through a Maya-only modal", %{conn: conn} do
    set_payments_mode!("qrph_manual")

    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("120")}],
        %{
          customer_name: "Maya QR Guest",
          fulfillment: :pickup,
          payment_method: :online,
          payment_intent: :maya
        }
      )

    assert order.payment_status == "awaiting_payment"

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#ticket-new-mark-paid-#{order.id}", "Confirm payment")
    view |> element("#ticket-new-mark-paid-#{order.id}") |> render_click()

    assert has_element?(view, "#mark-paid-modal-maya.is-suggested", "Maya")
    refute has_element?(view, "#mark-paid-modal-gcash")
    refute has_element?(view, "#mark-paid-modal-cash")

    view |> element("#mark-paid-modal-maya") |> render_click()

    reloaded = Orders.get_order_by_number!(order.number)
    assert reloaded.payment_status == "paid"
    assert reloaded.paid_via == "maya"
    assert reloaded.status == "preparing"
  end

  test "legacy qrph order without intent preserves the generic confirmation modal", %{conn: conn} do
    set_payments_mode!("qrph_manual")

    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("120")}],
        %{
          customer_name: "Legacy QR Guest",
          fulfillment: :pickup,
          payment_method: :online
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#ticket-new-mark-paid-#{order.id}", "Confirm payment")
    view |> element("#ticket-new-mark-paid-#{order.id}") |> render_click()

    assert has_element?(view, "#mark-paid-modal-gcash", "GCash")
    assert has_element?(view, "#mark-paid-modal-maya", "Maya")
    assert has_element?(view, "#mark-paid-modal-cash", "Paid cash instead")
  end

  test "noncanonical intent and channel combinations expose no payment path", %{conn: conn} do
    set_payments_mode!("qrph_manual")

    {:ok, counter_wallet} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Counter Wallet",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_intent: :gcash
        }
      )

    {:ok, online_cash} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("120")}],
        %{
          customer_name: "Online Cash",
          fulfillment: :pickup,
          payment_method: :online,
          payment_intent: :cash
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    for order <- [counter_wallet, online_cash] do
      refute has_element?(view, "#ticket-new-mark-paid-#{order.id}")
      refute has_element?(view, "#ticket-new-paid-via-cash-#{order.id}")
      refute has_element?(view, "#ticket-new-paid-via-gcash-#{order.id}")
      refute has_element?(view, "#ticket-new-paid-via-maya-#{order.id}")

      render_click(view, "open_mark_paid", %{"id" => Integer.to_string(order.id)})
      refute has_element?(view, "#mark-paid-modal")
    end
  end

  test "Cash modal rejects explicit wallets, PayMongo authority, paid, and cancelled orders", %{
    conn: conn
  } do
    set_payments_mode!("paymongo")

    wallet_orders =
      for wallet <- [:gcash, :maya] do
        {:ok, order} =
          Orders.create_order(
            [%{name: "Wallet", size: nil, quantity: 1, price: Decimal.new("100")}],
            %{
              customer_name: "#{wallet} Wallet",
              fulfillment: :pickup,
              payment_method: :online,
              payment_intent: wallet
            }
          )

        order
      end

    paid = cash_intent_order!("Already Paid Cash", "100")
    assert {:ok, paid} = Orders.mark_paid(paid, paid_via: "cash")
    cancelled = cash_intent_order!("Cancelled Cash", "100")
    assert {:ok, cancelled} = Orders.cancel_order(cancelled)

    {:ok, view, _html} = live(conn, ~p"/orders")

    for order <- wallet_orders ++ [paid, cancelled] do
      view
      |> render_click("open_cash_tender", %{"id" => Integer.to_string(order.id)})

      refute has_element?(view, "#orders-cash-tender-modal")
      assert has_element?(view, "#orders-flash", "Could not mark order paid.")
    end
  end

  test "counter unpaid shows Cash GCash Maya without the generic payment modal", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Modal Options",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#ticket-new-paid-via-cash-#{order.id}", "Cash")
    assert has_element?(view, "#ticket-new-paid-via-gcash-#{order.id}", "GCash")
    assert has_element?(view, "#ticket-new-paid-via-maya-#{order.id}", "Maya")
    refute has_element?(view, "#ticket-new-mark-paid-#{order.id}")
    refute has_element?(view, "#mark-paid-modal")
  end

  defp set_payments_mode!(mode) do
    setting = Espreso.BusinessSettings.get()

    setting
    |> Ecto.Changeset.change(%{payments_mode: mode})
    |> Espreso.Repo.update!()
  end

  defp detail_id(order_id, lane \\ "new"), do: "#order-detail-#{lane}-#{order_id}"

  defp mark_paid_via(view, order, paid_via, prefix, lane) do
    inline = "##{prefix}-#{lane}-paid-via-#{paid_via}-#{order.id}"

    if has_element?(view, inline) do
      view |> element(inline) |> render_click()
    else
      view
      |> element("##{prefix}-#{lane}-mark-paid-#{order.id}")
      |> render_click()

      view
      |> element("#mark-paid-modal-#{paid_via}")
      |> render_click()
    end

    if paid_via == "cash", do: confirm_cash_exact(view)
  end

  defp confirm_cash_exact(view) do
    view |> element("#orders-cash-exact") |> render_click()
    view |> form("#orders-cash-tender-form") |> render_submit()
  end

  defp cash_intent_order!(customer_name, total) do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Cash Item", size: nil, quantity: 1, price: Decimal.new(total)}],
        %{
          customer_name: customer_name,
          fulfillment: :pickup,
          payment_method: :counter,
          payment_intent: :cash
        }
      )

    order
  end

  test "notification bell shows new order and mark all read", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#staff-notif-toggle")
    refute has_element?(view, "#staff-notif-badge")

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Bell Test",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    _ = :sys.get_state(view.pid)
    html = render(view)

    assert html =~ "New order"
    assert html =~ order.number
    assert has_element?(view, "#staff-notif-badge")
    assert has_element?(view, "#orders-alert-banner", order.number)

    view |> element("#staff-notif-toggle") |> render_click()
    assert has_element?(view, "#staff-notif-panel")
    assert has_element?(view, "#staff-notif-list", "New order")

    view |> element("#staff-notif-mark-all") |> render_click()
    refute has_element?(view, "#staff-notif-badge")

    view |> element("#orders-alert-dismiss") |> render_click()
    refute has_element?(view, "#orders-alert-banner")
  end

  test "orders?unpaid=1 opens unpaid drawer", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Unpaid Deep",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders?unpaid=1")
    assert has_element?(view, "#unpaid-orders.staff-orders-unpaid-drawer--open")
    assert has_element?(view, "#unpaid-order-#{order.id}")
  end

  test "Mark Paid Cash permit dispatches one receipt and one drawer command", %{conn: conn} do
    restore_printer_config_on_exit()

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Mark Paid Physical", fulfillment: :pickup, payment_method: :counter}
      )

    {port, printer_task} = start_test_printer!(2)
    set_test_printer_port(port)
    {:ok, view, _html} = live(conn, ~p"/orders")
    permit = live_assigns(view).mark_paid_permits[order.id]

    assert has_element?(
             view,
             "#ticket-new-paid-via-cash-#{order.id}[phx-value-action='mark_paid'][phx-value-permit='#{permit}']"
           )

    view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()
    confirm_cash_exact(view)

    assert [receipt_bytes, drawer_bytes] = Task.await(printer_task, 2_000)
    assert receipt_bytes =~ order.number
    assert drawer_bytes == drawer_kick_bytes()
    assert Repo.get!(Espreso.Orders.Order, order.id).payment_status == "paid"
  end

  test "two LiveViews share one Mark Paid permit and the second causes no physical replay", %{
    conn: conn
  } do
    restore_printer_config_on_exit()

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Two Tabs", fulfillment: :pickup, payment_method: :counter}
      )

    {port, printer_task} = start_test_printer!(2)
    set_test_printer_port(port)
    {:ok, first_view, _html} = live(conn, ~p"/orders")
    {:ok, second_view, _html} = live(conn, ~p"/orders")

    permit = live_assigns(first_view).mark_paid_permits[order.id]
    assert live_assigns(second_view).mark_paid_permits[order.id] == permit

    first_view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()
    second_view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()
    assert has_element?(first_view, "#orders-cash-tender-modal")
    assert has_element?(second_view, "#orders-cash-tender-modal")

    confirm_cash_exact(first_view)
    assert [_receipt, drawer] = Task.await(printer_task, 2_000)
    assert drawer == drawer_kick_bytes()

    confirm_cash_exact(second_view)

    assert Process.alive?(second_view.pid)
    assert Repo.get!(Espreso.Orders.Order, order.id).payment_status == "paid"
  end

  test "Mark Paid Cash drawer retry does not reprint the receipt", %{conn: conn} do
    restore_printer_config_on_exit()

    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Drawer Recovery", fulfillment: :pickup, payment_method: :counter}
      )

    {receipt_port, receipt_task} = start_test_printer!(1)
    set_test_printer_port(receipt_port)
    {:ok, view, _html} = live(conn, ~p"/orders")
    view |> element("#ticket-new-paid-via-cash-#{order.id}") |> render_click()
    confirm_cash_exact(view)

    assert [receipt_bytes] = Task.await(receipt_task, 2_000)
    assert receipt_bytes =~ order.number

    recovery = live_assigns(view).mark_paid_recoveries[order.id]
    assert recovery.phase == :drawer
    assert is_binary(recovery.permit)

    {drawer_port, drawer_task} = start_test_printer!(1)
    set_test_printer_port(drawer_port)

    assert has_element?(
             view,
             "#open-drawer-#{order.id}[phx-click='retry_mark_paid'][phx-value-action='mark_paid'][phx-value-permit='#{recovery.permit}']"
           )

    view |> element("#open-drawer-#{order.id}") |> render_click()

    assert [drawer_bytes] = Task.await(drawer_task, 2_000)
    assert drawer_bytes == drawer_kick_bytes()
    refute Map.has_key?(live_assigns(view).mark_paid_recoveries, order.id)
  end

  test "stale Mark Paid event for a missing order is rejected without crashing", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Missing Mark Paid", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, view, _html} = live(conn, ~p"/orders")
    permit = live_assigns(view).mark_paid_permits[order.id]
    Repo.delete!(order)

    view
    |> render_click("mark_paid", %{
      "id" => to_string(order.id),
      "action" => "mark_paid",
      "permit" => permit,
      "paid_via" => "cash"
    })

    assert Process.alive?(view.pid)
    assert has_element?(view, "#orders-flash", "Could not mark order paid.")
  end

  test "cash Reprint dispatches one receipt, never opens the drawer, and allows a later permit",
       %{
         conn: conn
       } do
    restore_printer_config_on_exit()
    order = paid_order!("cash")
    {port, first_print} = start_test_printer!(1)
    set_test_printer_port(port)

    {:ok, view, _html} = live(conn, ~p"/orders")
    first_permit = live_assigns(view).reprint_permits[order.id]

    view |> element("#reprint-#{order.id}") |> render_click()

    assert [first_receipt] = Task.await(first_print, 2_000)
    refute first_receipt == drawer_kick_bytes()
    assert has_element?(view, "#orders-flash", "Receipt command dispatched.")

    second_permit = live_assigns(view).reprint_permits[order.id]
    assert is_binary(second_permit)
    refute second_permit == first_permit

    view
    |> render_click("reprint_receipt", %{
      "id" => to_string(order.id),
      "action" => "receipt_reprint",
      "permit" => first_permit
    })

    assert has_element?(
             view,
             "#orders-flash",
             "This Reprint request was already handled. No additional receipt was sent."
           )

    {next_port, second_print} = start_test_printer!(1)
    set_test_printer_port(next_port)
    view |> element("#reprint-#{order.id}") |> render_click()

    assert [second_receipt] = Task.await(second_print, 2_000)
    refute second_receipt == drawer_kick_bytes()
    assert has_element?(view, "#orders-flash", "Receipt command dispatched.")
  end

  test "wallet Reprint dispatches a receipt without a drawer command", %{conn: conn} do
    restore_printer_config_on_exit()
    order = paid_order!("gcash")
    {port, printer_task} = start_test_printer!(1)
    set_test_printer_port(port)

    {:ok, view, _html} = live(conn, ~p"/orders")
    view |> element("#reprint-#{order.id}") |> render_click()

    assert [receipt] = Task.await(printer_task, 2_000)
    refute receipt == drawer_kick_bytes()
    assert has_element?(view, "#orders-flash", "Receipt command dispatched.")
  end

  test "two LiveViews share a Reprint permit and its duplicate dispatches no receipt", %{
    conn: conn
  } do
    restore_printer_config_on_exit()
    order = paid_order!("cash")
    {port, printer_task} = start_test_printer!(1)
    set_test_printer_port(port)

    {:ok, first_view, _html} = live(conn, ~p"/orders")
    {:ok, second_view, _html} = live(conn, ~p"/orders")

    permit = live_assigns(first_view).reprint_permits[order.id]
    assert live_assigns(second_view).reprint_permits[order.id] == permit

    first_view |> element("#reprint-#{order.id}") |> render_click()
    assert [_receipt] = Task.await(printer_task, 2_000)

    second_view |> element("#reprint-#{order.id}") |> render_click()

    assert has_element?(
             second_view,
             "#orders-flash",
             "This Reprint request was already handled. No additional receipt was sent."
           )
  end

  test "definite Reprint connection failure exposes a fresh retry permit", %{conn: conn} do
    restore_printer_config_on_exit()
    set_test_printer_port(1)
    order = paid_order!("cash")

    {:ok, view, _html} = live(conn, ~p"/orders")
    first_permit = live_assigns(view).reprint_permits[order.id]

    view |> element("#reprint-#{order.id}") |> render_click()

    assert has_element?(
             view,
             "#orders-flash",
             "Reprint could not connect to the printer"
           )

    retry_permit = live_assigns(view).reprint_permits[order.id]
    assert is_binary(retry_permit)
    refute retry_permit == first_permit
  end

  test "Reprint rejects unpaid, missing, disabled, and wrong-order stale requests", %{conn: conn} do
    restore_printer_config_on_exit()
    set_test_printer_port(1)

    {:ok, unpaid} =
      Orders.create_order(
        [%{name: "Unpaid", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Unpaid", fulfillment: :pickup, payment_method: :counter}
      )

    unpaid_permit =
      PhysicalActionCoordinator.reprint_permits([unpaid.id])
      |> Map.fetch!(unpaid.id)

    {:ok, unpaid_view, _html} = live(conn, ~p"/orders")

    unpaid_view
    |> render_click("reprint_receipt", %{
      "id" => to_string(unpaid.id),
      "action" => "receipt_reprint",
      "permit" => unpaid_permit
    })

    assert has_element?(unpaid_view, "#orders-flash", "Only paid orders can be reprinted.")

    first = paid_order!("cash")
    second = paid_order!("cash")
    {:ok, paid_view, _html} = live(conn, ~p"/orders")
    first_permit = live_assigns(paid_view).reprint_permits[first.id]

    paid_view
    |> render_click("reprint_receipt", %{
      "id" => to_string(second.id),
      "action" => "receipt_reprint",
      "permit" => first_permit
    })

    assert has_element?(paid_view, "#orders-flash", "Reprint request is stale.")

    Repo.delete!(first)

    paid_view
    |> render_click("reprint_receipt", %{
      "id" => to_string(first.id),
      "action" => "receipt_reprint",
      "permit" => first_permit
    })

    assert has_element?(paid_view, "#orders-flash", "Order no longer exists.")

    disabled_order = paid_order!("cash")
    {:ok, disabled_view, _html} = live(conn, ~p"/orders")
    disabled_permit = live_assigns(disabled_view).reprint_permits[disabled_order.id]
    Application.put_env(:espreso, Printer, enabled: false, host: "")

    disabled_view
    |> render_click("reprint_receipt", %{
      "id" => to_string(disabled_order.id),
      "action" => "receipt_reprint",
      "permit" => disabled_permit
    })

    assert has_element?(disabled_view, "#orders-flash", "Printer is not enabled")
  end

  test "Kitchen and Kaha use separate permits, dispatch exact effects, and rearm", %{conn: conn} do
    restore_printer_config_on_exit()
    order = paid_order!("cash")
    {kitchen_port, kitchen_task} = start_test_printer!(1)
    set_test_printer_port(kitchen_port)

    {:ok, view, _html} = live(conn, ~p"/orders")
    kitchen_permit = live_assigns(view).kitchen_permits[order.id]
    drawer_permit = live_assigns(view).drawer_permits[order.id]

    assert has_element?(
             view,
             "#kitchen-#{order.id}[phx-value-action='kitchen'][phx-value-permit='#{kitchen_permit}']"
           )

    assert has_element?(
             view,
             "#open-drawer-#{order.id}[phx-value-id='#{order.id}'][phx-value-action='drawer'][phx-value-permit='#{drawer_permit}']"
           )

    view |> element("#kitchen-#{order.id}") |> render_click()
    assert [kitchen_bytes] = Task.await(kitchen_task, 2_000)
    assert kitchen_bytes =~ "KITCHEN"
    refute kitchen_bytes == drawer_kick_bytes()
    assert has_element?(view, "#orders-flash", "Kitchen ticket command dispatched.")

    next_kitchen = live_assigns(view).kitchen_permits[order.id]
    refute next_kitchen == kitchen_permit
    assert live_assigns(view).drawer_permits[order.id] == drawer_permit

    view
    |> render_click("print_kitchen", %{
      "id" => to_string(order.id),
      "action" => "kitchen",
      "permit" => kitchen_permit
    })

    assert has_element?(view, "#orders-flash", "already handled")

    {drawer_port, drawer_task} = start_test_printer!(1)
    set_test_printer_port(drawer_port)
    view |> element("#open-drawer-#{order.id}") |> render_click()

    assert [drawer_bytes] = Task.await(drawer_task, 2_000)
    assert drawer_bytes == drawer_kick_bytes()
    assert has_element?(view, "#orders-flash", "Kaha command dispatched.")

    next_drawer = live_assigns(view).drawer_permits[order.id]
    refute next_drawer == drawer_permit
    assert live_assigns(view).kitchen_permits[order.id] == next_kitchen

    view
    |> render_click("open_drawer", %{
      "id" => to_string(order.id),
      "action" => "drawer",
      "permit" => drawer_permit
    })

    assert has_element?(view, "#orders-flash", "Drawer was not opened again.")
  end

  test "unpaid operational orders retain protected Kitchen but do not expose Kaha", %{conn: conn} do
    restore_printer_config_on_exit()

    {:ok, order} =
      Orders.create_order(
        [%{name: "Unpaid Kitchen", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Kitchen", fulfillment: :pickup, payment_method: :counter}
      )

    {port, printer_task} = start_test_printer!(1)
    set_test_printer_port(port)
    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#kitchen-#{order.id}[phx-value-action='kitchen']")
    refute has_element?(view, "#open-drawer-#{order.id}")

    view |> element("#kitchen-#{order.id}") |> render_click()
    assert [kitchen_bytes] = Task.await(printer_task, 2_000)
    assert kitchen_bytes =~ "KITCHEN"
    assert Orders.get_order_by_number!(order.number).payment_status == "unpaid"
  end

  test "two LiveViews share Kitchen and Kaha permits and duplicates perform no second effect", %{
    conn: conn
  } do
    restore_printer_config_on_exit()
    order = paid_order!("cash")
    {kitchen_port, kitchen_task} = start_test_printer!(1)
    set_test_printer_port(kitchen_port)

    {:ok, first_view, _html} = live(conn, ~p"/orders")
    {:ok, second_view, _html} = live(conn, ~p"/orders")

    kitchen_permit = live_assigns(first_view).kitchen_permits[order.id]
    drawer_permit = live_assigns(first_view).drawer_permits[order.id]
    assert live_assigns(second_view).kitchen_permits[order.id] == kitchen_permit
    assert live_assigns(second_view).drawer_permits[order.id] == drawer_permit

    first_view |> element("#kitchen-#{order.id}") |> render_click()
    assert [_kitchen] = Task.await(kitchen_task, 2_000)
    second_view |> element("#kitchen-#{order.id}") |> render_click()
    assert has_element?(second_view, "#orders-flash", "No additional ticket was sent.")

    {drawer_port, drawer_task} = start_test_printer!(1)
    set_test_printer_port(drawer_port)
    first_view |> element("#open-drawer-#{order.id}") |> render_click()
    assert [drawer_bytes] = Task.await(drawer_task, 2_000)
    assert drawer_bytes == drawer_kick_bytes()
    second_view |> element("#open-drawer-#{order.id}") |> render_click()
    assert has_element?(second_view, "#orders-flash", "Drawer was not opened again.")
  end

  test "Kitchen and Kaha reject wrong, missing, ineligible, and disabled stale events", %{
    conn: conn
  } do
    restore_printer_config_on_exit()
    set_test_printer_port(1)
    cash_order = paid_order!("cash")
    wallet_order = paid_order!("gcash")

    {:ok, view, _html} = live(conn, ~p"/orders")
    kitchen_permit = live_assigns(view).kitchen_permits[cash_order.id]
    drawer_permit = live_assigns(view).drawer_permits[cash_order.id]

    view
    |> render_click("open_drawer", %{
      "id" => to_string(cash_order.id),
      "action" => "drawer",
      "permit" => kitchen_permit
    })

    assert has_element?(view, "#orders-flash", "Kaha request is stale.")

    view
    |> render_click("open_drawer", %{
      "id" => to_string(wallet_order.id),
      "action" => "drawer",
      "permit" => drawer_permit
    })

    assert has_element?(view, "#orders-flash", "Kaha request is stale.")

    wallet_drawer_permit =
      PhysicalActionCoordinator.permits(:drawer, [wallet_order.id])
      |> Map.fetch!(wallet_order.id)

    view
    |> render_click("open_drawer", %{
      "id" => to_string(wallet_order.id),
      "action" => "drawer",
      "permit" => wallet_drawer_permit
    })

    assert has_element?(view, "#orders-flash", "only available for cash-like payments")

    {:ok, unpaid} =
      Orders.create_order(
        [%{name: "Unpaid", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Unpaid", fulfillment: :pickup, payment_method: :counter}
      )

    unpaid_drawer_permit =
      PhysicalActionCoordinator.permits(:drawer, [unpaid.id])
      |> Map.fetch!(unpaid.id)

    view
    |> render_click("open_drawer", %{
      "id" => to_string(unpaid.id),
      "action" => "drawer",
      "permit" => unpaid_drawer_permit
    })

    assert has_element?(view, "#orders-flash", "Only paid orders can open Kaha.")

    missing_kitchen_permit =
      PhysicalActionCoordinator.permits(:kitchen, [unpaid.id])
      |> Map.fetch!(unpaid.id)

    Repo.delete!(unpaid)

    view
    |> render_click("print_kitchen", %{
      "id" => to_string(unpaid.id),
      "action" => "kitchen",
      "permit" => missing_kitchen_permit
    })

    assert has_element?(view, "#orders-flash", "Order no longer exists.")

    {:ok, cancelled} =
      Orders.create_order(
        [%{name: "Cancelled", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Cancelled", fulfillment: :pickup, payment_method: :counter}
      )

    cancelled_kitchen_permit =
      PhysicalActionCoordinator.permits(:kitchen, [cancelled.id])
      |> Map.fetch!(cancelled.id)

    {:ok, cancelled} = Orders.cancel_order(cancelled)

    view
    |> render_click("print_kitchen", %{
      "id" => to_string(cancelled.id),
      "action" => "kitchen",
      "permit" => cancelled_kitchen_permit
    })

    assert has_element?(view, "#orders-flash", "no longer eligible for Kitchen")

    missing_drawer = paid_order!("cash")

    missing_drawer_permit =
      PhysicalActionCoordinator.permits(:drawer, [missing_drawer.id])
      |> Map.fetch!(missing_drawer.id)

    Repo.delete!(missing_drawer)

    view
    |> render_click("open_drawer", %{
      "id" => to_string(missing_drawer.id),
      "action" => "drawer",
      "permit" => missing_drawer_permit
    })

    assert has_element?(view, "#orders-flash", "Order no longer exists.")

    {:ok, ready} = Orders.update_status(cash_order, "ready")
    {:ok, completed} = Orders.complete_order(ready)

    view
    |> render_click("print_kitchen", %{
      "id" => to_string(completed.id),
      "action" => "kitchen",
      "permit" => kitchen_permit
    })

    assert has_element?(view, "#orders-flash", "no longer eligible for Kitchen")

    view
    |> render_click("open_drawer", %{
      "id" => to_string(completed.id),
      "action" => "drawer",
      "permit" => drawer_permit
    })

    assert has_element?(view, "#orders-flash", "no longer eligible for Kaha")

    disabled_order = paid_order!("cash")
    {:ok, disabled_view, _html} = live(conn, ~p"/orders")
    disabled_kitchen = live_assigns(disabled_view).kitchen_permits[disabled_order.id]
    disabled_drawer = live_assigns(disabled_view).drawer_permits[disabled_order.id]
    Application.put_env(:espreso, Printer, enabled: false, host: "")

    disabled_view
    |> render_click("print_kitchen", %{
      "id" => to_string(disabled_order.id),
      "action" => "kitchen",
      "permit" => disabled_kitchen
    })

    assert has_element?(disabled_view, "#orders-flash", "No kitchen ticket was sent.")

    disabled_view
    |> render_click("open_drawer", %{
      "id" => to_string(disabled_order.id),
      "action" => "drawer",
      "permit" => disabled_drawer
    })

    assert has_element?(disabled_view, "#orders-flash", "Drawer was not opened.")
  end

  test "Kitchen and Kaha definite failures rotate only their own retry permits", %{conn: conn} do
    restore_printer_config_on_exit()
    set_test_printer_port(1)
    order = paid_order!("cash")
    {:ok, view, _html} = live(conn, ~p"/orders")

    kitchen_permit = live_assigns(view).kitchen_permits[order.id]
    drawer_permit = live_assigns(view).drawer_permits[order.id]

    view |> element("#kitchen-#{order.id}") |> render_click()
    kitchen_retry = live_assigns(view).kitchen_permits[order.id]
    refute kitchen_retry == kitchen_permit
    assert live_assigns(view).drawer_permits[order.id] == drawer_permit
    assert has_element?(view, "#orders-flash", "Kitchen could not connect")

    view |> element("#open-drawer-#{order.id}") |> render_click()
    drawer_retry = live_assigns(view).drawer_permits[order.id]
    refute drawer_retry == drawer_permit
    assert live_assigns(view).kitchen_permits[order.id] == kitchen_retry
    assert has_element?(view, "#orders-flash", "Kaha could not connect")
  end

  defp paid_order!(paid_via) do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{customer_name: "Reprint", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, paid} = Orders.mark_paid(order, paid_via: paid_via)
    paid
  end

  defp live_assigns(view) do
    view.pid
    |> :sys.get_state()
    |> Map.fetch!(:socket)
    |> Map.fetch!(:assigns)
  end

  defp restore_printer_config_on_exit do
    previous = Application.get_env(:espreso, Printer)

    on_exit(fn ->
      if previous do
        Application.put_env(:espreso, Printer, previous)
      else
        Application.delete_env(:espreso, Printer)
      end
    end)
  end

  defp set_test_printer_port(port) do
    Application.put_env(
      :espreso,
      Printer,
      enabled: true,
      host: "127.0.0.1",
      port: port,
      timeout_ms: 1_000
    )
  end

  defp start_test_printer!(connection_count) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_address, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        bytes =
          Enum.map(1..connection_count, fn _ ->
            {:ok, socket} = :gen_tcp.accept(listener, 1_500)
            {:ok, bytes} = :gen_tcp.recv(socket, 0, 1_500)
            :gen_tcp.close(socket)
            bytes
          end)

        :gen_tcp.close(listener)
        bytes
      end)

    {port, task}
  end

  defp drawer_kick_bytes, do: <<0x1B, 0x70, 0x00, 0x19, 0xFA>>

  defp backdate_order!(order, minutes_ago: minutes) when is_integer(minutes) and minutes >= 0 do
    at =
      DateTime.utc_now(:second)
      |> DateTime.add(-minutes * 60, :second)

    Espreso.Repo.update_all(
      from(o in Espreso.Orders.Order, where: o.id == ^order.id),
      set: [inserted_at: at, updated_at: at]
    )
  end

  defp backdate_order!(order, seconds_ago: seconds) when is_integer(seconds) and seconds >= 0 do
    at =
      DateTime.utc_now(:second)
      |> DateTime.add(-seconds, :second)

    Espreso.Repo.update_all(
      from(o in Espreso.Orders.Order, where: o.id == ^order.id),
      set: [inserted_at: at, updated_at: at]
    )
  end
end
