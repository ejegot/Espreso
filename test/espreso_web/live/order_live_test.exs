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
    assert has_element?(view, "a.order-more-link", "Order More")
    assert has_element?(view, "#order-receipt", "Your order")
    assert has_element?(view, "#order-receipt .order-total", "₱75")
    assert has_element?(view, "#order-receipt .order-payment", "Pay at counter")
    assert has_element?(view, "#order-progress")

    assert has_element?(
             view,
             ~s(#order-progress [data-step="received"][data-state="current"][aria-current="step"])
           )

    refute html =~ "Status: "
    refute has_element?(view, "#order-confirm")

    more_href =
      view
      |> element("#order-order-more")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")
      |> List.first()

    assert more_href == "/menu?stage=menu"

    assert {:ok, preparing} = Orders.update_status(order, "preparing")
    assert has_element?(view, "#order-status-message", "We're preparing your order")
    assert has_element?(view, "#order-hint", "We're preparing it — keep this screen for updates.")
    assert has_element?(view, ~s(#order-progress [data-step="received"][data-state="completed"]))

    assert has_element?(
             view,
             ~s(#order-progress [data-step="preparing"][data-state="current"][aria-current="step"])
           )

    refute render(view) =~ ~r/Order received/

    assert {:ok, _} = Orders.update_status(preparing, "ready")
    assert has_element?(view, "#order-status-message", "Your order is ready")
    assert has_element?(view, "#order-hint", "Payment is due at the counter")

    assert has_element?(
             view,
             ~s(#order-progress [data-step="ready"][data-state="current"][aria-current="step"])
           )

    refute render(view) =~ ~r/Order received/

    assert {:ok, _} = Orders.mark_paid(preparing)
    assert render(view) =~ "Paid at counter"

    assert has_element?(
             view,
             "#order-hint",
             "Your order is ready — show this screen at the counter."
           )

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
    assert has_element?(view, "#order-complete-state")
    assert has_element?(view, ".order-complete-badge", "Order complete")
    assert has_element?(view, "#order-status-message", "Picked Up ✓")

    assert has_element?(
             view,
             "#order-hint",
             "Your order has been picked up. Thank you for visiting CoffeeSpot."
           )

    refute has_element?(view, "#order-progress")
    assert has_element?(view, "#order-receipt")
    assert has_element?(view, ".order-number", order.number)

    hint = view |> element("#order-hint") |> render()
    refute hint =~ ~r/pay/i
    refute hint =~ ~r/claim/i
    refute render(view) =~ ~r/Order received/
    assert has_element?(view, "a.order-more-link", "Order More")
  end

  test "customer order confirmation shows View My Order and Order More", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Confirm Flow",
          fulfillment: :pickup,
          payment_method: :counter
        }
      )

    {:ok, view, html} = live(conn, ~p"/order/#{order.number}?confirm=1")

    assert has_element?(view, "#order-confirm")
    assert has_element?(view, "#order-confirm-title", "Order confirmed")
    assert has_element?(view, "#order-confirm-number", order.number)
    assert has_element?(view, ~s(#order-confirm[data-order-number="#{order.number}"]))
    assert has_element?(view, "#order-view-my-order", "View My Order")
    assert has_element?(view, "#order-order-more", "Order More")
    assert html =~ ~s(phx-hook="OrderConfirm")
    refute has_element?(view, "#order-status-message")
    refute has_element?(view, "#order-receipt")

    view_href =
      view
      |> element("#order-view-my-order")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")
      |> List.first()

    more_href =
      view
      |> element("#order-order-more")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")
      |> List.first()

    assert view_href == "/order/#{order.number}"
    assert more_href == "/menu?stage=menu"

    {:ok, detail_view, _html} =
      view
      |> element("#order-view-my-order", "View My Order")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(detail_view, "#order-status-message", "Order received")
    assert has_element?(detail_view, ".order-number", order.number)
    assert has_element?(detail_view, "#order-receipt", "Espresso")
    refute has_element?(detail_view, "#order-confirm")

    {:ok, menu_view, _html} =
      detail_view
      |> element("#order-order-more", "Order More")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(menu_view, "#menu-items")
    refute has_element?(menu_view, "#menu-landing")
  end

  test "online unpaid confirm shows payment processing until paid", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}],
        %{
          customer_name: "Online Confirm",
          fulfillment: :pickup,
          payment_method: :online
        }
      )

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_confirm_live")
    assert order.payment_status == "unpaid"

    {:ok, view, _html} = live(conn, ~p"/order/#{order.number}?confirm=1")

    assert has_element?(view, "#order-confirm")
    assert has_element?(view, "#order-confirm-title", "Payment processing")

    assert has_element?(
             view,
             "#order-confirm-lede",
             "We’re confirming your payment. This page will update when it’s done."
           )

    refute has_element?(view, "#order-confirm-title", "Order confirmed")
    refute has_element?(view, "#order-status-message")

    assert {:ok, _} = Orders.mark_paid(order)
    assert has_element?(view, "#order-confirm-title", "Order confirmed")

    assert has_element?(
             view,
             "#order-confirm-lede",
             "Your order is in. Show your order number at the counter when you pick it up."
           )

    refute has_element?(view, "#order-confirm-title", "Payment processing")
  end

  test "online paid confirm shows order confirmed", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}],
        %{
          customer_name: "Already Paid",
          fulfillment: :pickup,
          payment_method: :online
        }
      )

    {:ok, order} = Orders.attach_paymongo_session(order, "cs_confirm_paid")
    {:ok, order} = Orders.mark_paid(order)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.number}?confirm=1")

    assert has_element?(view, "#order-confirm-title", "Order confirmed")
    refute has_element?(view, "#order-confirm-title", "Payment processing")
  end

  test "online order without confirm shows normal detail", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("100")}],
        %{
          customer_name: "Online Detail",
          fulfillment: :pickup,
          payment_method: :online
        }
      )

    {:ok, _order} = Orders.attach_paymongo_session(order, "cs_confirm_detail")

    {:ok, view, _html} = live(conn, ~p"/order/#{order.number}")

    refute has_element?(view, "#order-confirm")
    assert has_element?(view, "#order-status-message", "Order received")
    assert has_element?(view, "#order-receipt .order-payment", "Awaiting online payment")
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
    assert has_element?(view, "a.order-more-link", "Order More")
    assert has_element?(view, "#order-receipt")
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

    assert has_element?(
             view,
             "#order-hint",
             "Your order is ready — show this screen at the counter."
           )

    assert has_element?(view, ~s(#order-progress [data-step="ready"][aria-current="step"]))

    assert {:ok, _} = Orders.complete_order(ready)
    assert has_element?(view, "#order-status-message", "Picked Up ✓")
    assert has_element?(view, "#order-hint", "Your order has been picked up")
    assert has_element?(view, "#order-complete-state")
    refute has_element?(view, "#order-progress")
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
