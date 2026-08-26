defmodule EspresoWeb.OrderLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Orders

  test "customer order page shows status-driven messaging and live updates", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Customer Live",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, html} = live(conn, ~p"/order/#{order.number}")
    assert has_element?(view, "#order-status-message", "Order received")
    assert has_element?(view, "#order-hint", "Payment is due at the counter")
    assert html =~ "Pay at counter"
    assert has_element?(view, "a.brune-primary-btn", "Order more")
    assert has_element?(view, "#order-progress")
    assert has_element?(view, ~s(#order-progress [data-step="received"][data-state="current"][aria-current="step"]))
    refute html =~ "Status: "

    assert {:ok, preparing} = Orders.update_status(order, "preparing")
    assert has_element?(view, "#order-status-message", "We're preparing your order")
    assert has_element?(view, "#order-hint", "We're preparing it — keep this screen for updates.")
    assert has_element?(view, ~s(#order-progress [data-step="received"][data-state="completed"]))
    assert has_element?(view, ~s(#order-progress [data-step="preparing"][data-state="current"][aria-current="step"]))
    refute render(view) =~ ~r/Order received/

    assert {:ok, _} = Orders.update_status(preparing, "ready")
    assert has_element?(view, "#order-status-message", "Your order is ready")
    assert has_element?(view, "#order-hint", "Payment is due at the counter")
    assert has_element?(view, ~s(#order-progress [data-step="ready"][data-state="current"][aria-current="step"]))
    refute render(view) =~ ~r/Order received/

    assert {:ok, _} = Orders.mark_paid(preparing)
    assert render(view) =~ "Paid at counter"
    assert has_element?(view, "#order-hint", "Your order is ready — show this screen at the counter.")
    refute render(view) =~ "Payment is due at the counter"
  end

  test "customer order page updates when picked up", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Customer Complete",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, ready} = Orders.update_status(order, "ready")
    {:ok, view, html} = live(conn, ~p"/order/#{order.number}")
    assert has_element?(view, "#order-status-message", "Your order is ready")
    assert has_element?(view, ~s(#order-progress [data-step="ready"][data-state="current"]))
    refute html =~ ~r/>Order received</

    assert {:ok, _} = Orders.complete_order(ready)
    assert has_element?(view, "#order-status-message", "Order picked up")
    assert has_element?(
             view,
             "#order-hint",
             "Thanks — this order is complete. We hope you enjoyed CoffeeSpot."
           )
    assert has_element?(view, ~s(#order-progress [data-step="received"][data-state="completed"]))
    assert has_element?(view, ~s(#order-progress [data-step="preparing"][data-state="completed"]))
    assert has_element?(view, ~s(#order-progress [data-step="ready"][data-state="completed"]))
    assert has_element?(
             view,
             ~s(#order-progress [data-step="completed"][data-state="current"][aria-current="step"]),
             "Picked up"
           )

    hint = view |> element("#order-hint") |> render()
    refute hint =~ ~r/pay/i
    refute hint =~ ~r/claim/i
    refute render(view) =~ ~r/Order received/
    assert has_element?(view, "a.brune-primary-btn", "Order more")
  end

  test "customer order page updates when cancelled", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Customer Cancel",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/order/#{order.number}")
    assert has_element?(view, "#order-status-message", "Order received")
    assert has_element?(view, "#order-progress")

    assert {:ok, _} = Orders.cancel_order(order)
    assert has_element?(view, "#order-status-message", "Order cancelled")
    assert has_element?(view, "#order-cancelled-state", "Cancelled")
    assert has_element?(view, "#order-cancelled-state", "This order will not be prepared.")
    refute has_element?(view, "#order-progress")
    assert has_element?(
             view,
             "#order-hint",
             "This order was cancelled. You can place a new order from the menu."
           )

    hint = view |> element("#order-hint") |> render()
    refute hint =~ ~r/pay/i
    refute hint =~ ~r/claim/i
    refute render(view) =~ ~r/Order received/
    assert has_element?(view, "a.brune-primary-btn", "Order more")
  end

  test "each order status shows the matching customer message", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Status Copy",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/order/#{order.number}")
    assert has_element?(view, "#order-status-message", "Order received")
    assert has_element?(view, "#order-hint", "Keep this screen and show it at the counter")
    assert has_element?(view, ~s(#order-progress [data-step="received"][aria-current="step"]))
    assert has_element?(view, ~s(#order-progress [data-step="preparing"][data-state="upcoming"]))
    assert has_element?(view, ~s(#order-progress [data-step="ready"][data-state="upcoming"]))
    assert has_element?(view, ~s(#order-progress [data-step="completed"][data-state="upcoming"]))

    assert {:ok, preparing} = Orders.update_status(order, "preparing")
    assert has_element?(view, "#order-status-message", "We're preparing your order")
    assert has_element?(view, "#order-hint", "We're preparing it — keep this screen for updates.")
    assert has_element?(view, ~s(#order-progress [data-step="preparing"][aria-current="step"]))

    assert {:ok, ready} = Orders.update_status(preparing, "ready")
    assert has_element?(view, "#order-status-message", "Your order is ready")
    assert has_element?(view, "#order-hint", "Your order is ready — show this screen at the counter.")
    assert has_element?(view, ~s(#order-progress [data-step="ready"][aria-current="step"]))

    assert {:ok, _} = Orders.complete_order(ready)
    assert has_element?(view, "#order-status-message", "Order picked up")
    assert has_element?(view, "#order-hint", "Thanks — this order is complete")
    assert has_element?(view, ~s(#order-progress [data-step="completed"][aria-current="step"]))
  end

  test "paid preparing order does not tell the customer to pay", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Paid Prep",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    assert {:ok, _} = Orders.mark_paid(order)
    assert {:ok, _} = Orders.update_status(order, "preparing")

    {:ok, view, html} = live(conn, ~p"/order/#{order.number}")
    assert has_element?(view, "#order-status-message", "We're preparing your order")
    assert has_element?(view, "#order-hint", "We're preparing it — keep this screen for updates.")
    assert has_element?(view, ~s(#order-progress [data-step="preparing"][data-state="current"]))
    assert html =~ "Paid at counter"
    refute has_element?(view, "#order-hint", "Payment is due")
    refute render(view) =~ ~r/claim/i
  end
end
