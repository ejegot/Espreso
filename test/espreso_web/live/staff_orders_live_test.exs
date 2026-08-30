defmodule EspresoWeb.StaffOrdersLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Espreso.Accounts
  alias Espreso.Orders

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

  test "new ticket shows items, payment, and Prepare as primary action", %{conn: conn} do
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

    assert has_element?(view, "#order-card-#{order.id} .staff-order-number", order.number)
    assert has_element?(view, "#order-card-#{order.id} .staff-order-name", "Juan")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "2 ×")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "Iced Latte")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "16oz")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "1 ×")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "Muffin")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-pay", "₱325")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-pay", "Unpaid")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-age", "Just now")
    assert has_element?(view, "#order-prepare-#{order.id}.staff-action-primary", "Prepare")
    refute has_element?(view, "#order-ready-#{order.id}")
    refute has_element?(view, "#order-card-#{order.id} .staff-badge--received")
  end

  test "Prepare moves order to preparing with Ready as primary action", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Mia",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    view
    |> element("#order-prepare-#{order.id}", "Prepare")
    |> render_click()

    assert has_element?(view, "#orders-preparing #order-card-#{order.id}")
    assert has_element?(view, "#order-ready-#{order.id}.staff-action-primary", "Ready")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "Espresso")
    refute has_element?(view, "#order-prepare-#{order.id}")
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

    {:ok, view, _html} = live(conn, ~p"/orders")

    view |> element("#order-prepare-#{order.id}") |> render_click()
    view |> element("#order-ready-#{order.id}", "Ready") |> render_click()

    assert has_element?(view, "#orders-ready #order-card-#{order.id}")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "Spanish Latte")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-pay", "Unpaid")
    assert has_element?(view, "#ready-complete-#{order.id}.staff-action-primary", "Picked up")
    assert has_element?(view, "#ready-mark-paid-#{order.id}.staff-action-secondary", "Mark paid")
    refute has_element?(view, "#order-card-#{order.id}.staff-order-card-muted")
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
    assert has_element?(view, "#orders-kitchen #order-card-#{order.id}")
    assert has_element?(view, detail_id(order.id))

    assert has_element?(view, "#unpaid-orders[aria-label='Unpaid orders']")
    assert has_element?(view, ".staff-orders-collections#unpaid-orders")
    refute has_element?(view, "#orders-kitchen #unpaid-orders")
    assert has_element?(view, "#unpaid-order-#{order.id}")
    assert has_element?(view, "#unpaid-drawer-toggle")
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
    assert Orders.list_active_orders() == []
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
    assert has_element?(view, "#unpaid-mark-paid-#{order.id}")

    view
    |> element("#unpaid-mark-paid-#{order.id}")
    |> render_click()

    refute has_element?(view, "#cancel-order-#{order.id}")
    refute has_element?(view, "#unpaid-order-#{order.id}")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-pay", "Paid")
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

    {:ok, view, _html} = live(conn, ~p"/orders")

    view |> element("#order-prepare-#{order.id}") |> render_click()
    view |> element("#order-ready-#{order.id}") |> render_click()

    refute has_element?(view, "#cancel-order-#{order.id}")
    assert has_element?(view, "#orders-ready .staff-order-number", order.number)
  end

  test "ready unpaid order can be marked paid", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Ready Unpaid",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/orders")

    view |> element("#order-prepare-#{order.id}") |> render_click()
    view |> element("#order-ready-#{order.id}") |> render_click()

    assert has_element?(view, "#ready-mark-paid-#{order.id}", "Mark paid")

    view |> element("#ready-mark-paid-#{order.id}") |> render_click()

    assert has_element?(view, "#orders-flash", "#{order.number} marked paid.")
    refute has_element?(view, "#ready-mark-paid-#{order.id}")
    assert has_element?(view, ".staff-order-number", order.number)
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-pay", "Paid")

    reloaded = Orders.get_order_by_number!(order.number)
    assert reloaded.payment_status == "paid"
    assert reloaded.payment_method == "counter"
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
    refute has_element?(view, "#ready-mark-paid-#{order.id}")
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

    {:ok, view, _html} = live(conn, ~p"/orders")

    view |> element("#order-prepare-#{order.id}") |> render_click()
    view |> element("#order-ready-#{order.id}") |> render_click()

    assert has_element?(view, "#ready-mark-paid-#{order.id}", "Mark paid")
    assert has_element?(view, "#ready-complete-#{order.id}", "Picked up")
    refute has_element?(view, "#cancel-order-#{order.id}")

    view |> element("#ready-complete-#{order.id}") |> render_click()

    assert has_element?(view, "#orders-flash", "#{order.number} picked up.")
    refute has_element?(view, "#ready-complete-#{order.id}")
    refute has_element?(view, "#orders-ready .staff-order-number", order.number)
    assert has_element?(view, "#unpaid-order-#{order.id}")

    reloaded = Orders.get_order_by_number!(order.number)
    assert reloaded.status == "completed"
    assert reloaded.payment_status == "unpaid"
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

    {:ok, _} = Orders.update_status(order, "ready")
    {:ok, view, _html} = live(conn, ~p"/orders")
    assert has_element?(view, "#ready-complete-#{order.id}")

    assert {:ok, _} = Orders.complete_order(order)
    html = render(view)
    refute has_element?(view, "#ready-complete-#{order.id}")
    assert has_element?(view, "#unpaid-order-#{order.id}")
    assert html =~ order.number
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

    assert {:ok, _} = Orders.update_status(order, "ready")
    html = render(view)
    assert html =~ "No new orders."
    assert html =~ "Nothing preparing."
    assert has_element?(view, "#orders-ready .staff-order-number", order.number)
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "Espresso")
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

    view |> element("button.staff-shell-tool", "Refresh") |> render_click()

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

    {:ok, _} = Orders.update_status(order, "ready")
    {:ok, _} = Orders.complete_order(order)

    html = render(view)
    assert html =~ "Unpaid Today"
    assert has_element?(view, "#unpaid-order-#{order.id}")
    assert has_element?(view, "#unpaid-order-#{order.id} .staff-order-number", order.number)
    assert has_element?(view, "#unpaid-order-#{order.id} .staff-order-name", "Unpaid Visible")
    assert has_element?(view, "#unpaid-order-#{order.id} .staff-badge--completed", "Picked up")
    assert has_element?(view, "#unpaid-order-#{order.id} .staff-badge--pay-unpaid", "Unpaid")
    assert has_element?(view, "#unpaid-order-#{order.id} .staff-order-pay", "₱75")
    assert has_element?(view, "#unpaid-mark-paid-#{order.id}", "Mark paid")
    refute has_element?(view, "#unpaid-orders-empty")

    view |> element("#unpaid-mark-paid-#{order.id}") |> render_click()

    assert has_element?(view, "#orders-flash", "#{order.number} marked paid.")
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
    {:ok, _} = Orders.update_status(preparing, "preparing")
    {:ok, _} = Orders.update_status(ready, "ready")

    {:ok, view, _html} = live(conn, ~p"/orders")

    assert has_element?(view, "#orders-new #order-card-#{fresh.id} .staff-order-age", "Just now")
    refute has_element?(view, "#orders-new #order-card-#{fresh.id} .staff-order-age--attention")

    assert has_element?(
             view,
             "#orders-preparing #order-card-#{preparing.id} .staff-order-age--attention",
             "5 min ago"
           )

    assert has_element?(
             view,
             "#orders-ready #order-card-#{ready.id} .staff-order-age--urgent",
             "10 min ago"
           )

    assert has_element?(view, "#order-prepare-#{fresh.id}.staff-action-primary", "Prepare")
    assert has_element?(view, "#order-ready-#{preparing.id}.staff-action-primary", "Ready")
    assert has_element?(view, "#ready-complete-#{ready.id}.staff-action-primary", "Picked up")

    reloaded = Orders.get_order_by_number!(fresh.number)
    assert reloaded.status == "received"
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
             "#order-card-#{order.id} .staff-order-age--critical",
             "16 min ago"
           )

    assert has_element?(view, "#order-prepare-#{order.id}", "Prepare")
    assert Orders.get_order_by_number!(order.number).status == "received"
  end

  test "customer source shows QR badge; pos source shows WALK-IN badge", %{conn: conn} do
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

    {:ok, pos_order} =
      Orders.create_order(
        [%{name: "Americano", size: "8oz", quantity: 1, price: Decimal.new("110")}],
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
             "#order-source-#{qr_order.id}.staff-order-source--customer",
             "QR"
           )

    assert has_element?(
             view,
             "#order-source-#{pos_order.id}.staff-order-source--pos",
             "WALK-IN"
           )

    assert has_element?(view, "#order-card-#{qr_order.id} .staff-order-name", "QR Guest")
    assert has_element?(view, "#order-card-#{pos_order.id} .staff-order-name", "Walk-in")
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
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-meta", "Table 5")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-items", "12oz")
    assert has_element?(view, "#order-prepare-#{order.id}", "Prepare")
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

    assert has_element?(view, "#orders-ready #order-card-#{oldest.id}")
    assert has_element?(view, "#orders-ready #order-card-#{newest.id}")

    assert has_element?(view, "#ready-complete-#{oldest.id}", "Picked up")
    assert has_element?(view, "#orders-ready .staff-orders-count", "11")
  end

  test "unpaid Ready order keeps Picked up as final action and Mark paid available", %{
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
    view |> element("#order-prepare-#{order.id}") |> render_click()
    view |> element("#order-ready-#{order.id}") |> render_click()

    assert has_element?(view, "#orders-ready #order-card-#{order.id}")
    assert has_element?(view, "#{detail_id(order.id)} .staff-order-pay", "Unpaid")
    assert has_element?(view, "#ready-complete-#{order.id}.staff-action-primary", "Picked up")
    assert has_element?(view, "#ready-complete-#{order.id}.staff-action-complete", "Picked up")
    assert has_element?(view, "#ready-mark-paid-#{order.id}.staff-action-secondary", "Mark paid")

    view |> element("#ready-complete-#{order.id}") |> render_click()

    reloaded = Orders.get_order_by_number!(order.number)
    assert reloaded.status == "completed"
    assert reloaded.payment_status == "unpaid"
    refute has_element?(view, "#orders-ready #order-card-#{order.id}")
    assert has_element?(view, "#unpaid-order-#{order.id}")
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
    assert has_element?(view, "#order-prepare-#{first.id}", "Prepare")
    assert has_element?(view, "#order-prepare-#{second.id}", "Prepare")
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

  defp detail_id(order_id), do: "#order-detail-#{order_id}"

  defp backdate_order!(order, minutes_ago: minutes) when is_integer(minutes) and minutes >= 0 do
    at =
      DateTime.utc_now(:second)
      |> DateTime.add(-minutes * 60, :second)

    Espreso.Repo.update_all(
      from(o in Espreso.Orders.Order, where: o.id == ^order.id),
      set: [inserted_at: at, updated_at: at]
    )
  end
end
