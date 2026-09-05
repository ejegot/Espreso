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
    assert has_element?(view, "#order-chrome")
    assert has_element?(view, "#order-chrome-title", "Your order")
    assert has_element?(view, "#order-chrome-back[aria-label='Back to menu']")
    refute has_element?(view, ".brune-top")
    refute has_element?(view, ".brune-top-leading")
    refute has_element?(view, ".brune-top-trailing")
    assert has_element?(view, "#order-status-message", "Received — kitchen has it")
    assert has_element?(view, "#order-hint", "Pay at counter · show this number.")
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
    assert has_element?(view, "#order-status-message", "Preparing your order")
    assert has_element?(view, "#order-hint", "We're preparing it — keep this screen for updates.")
    assert has_element?(view, ~s(#order-progress [data-step="received"][data-state="completed"]))

    assert has_element?(
             view,
             ~s(#order-progress [data-step="preparing"][data-state="current"][aria-current="step"])
           )

    refute render(view) =~ "Received — kitchen has it"

    assert {:ok, _} = Orders.mark_paid(preparing)
    assert {:ok, _} = Orders.update_status(preparing, "ready")
    assert has_element?(view, "#order-status-message", "Ready — please come to counter")
    assert has_element?(view, "#order-hint", "Show #{order.number} at the counter")
    refute has_element?(view, "#order-hint", "Payment is due at the counter")

    assert has_element?(
             view,
             ~s(#order-progress [data-step="ready"][data-state="current"][aria-current="step"])
           )

    refute render(view) =~ "Received — kitchen has it"

    assert render(view) =~ "Paid at counter"
    assert has_element?(view, "#order-paid-badge", "Paid ✓")

    assert has_element?(
             view,
             "#order-hint",
             "Show #{order.number} at the counter."
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

    {:ok, _} = Orders.mark_paid(order)
    {:ok, ready} = Orders.update_status(order, "ready")
    {:ok, view, html} = live(conn, ~p"/order/#{order.number}")
    assert has_element?(view, "#order-status-message", "Ready — please come to counter")
    assert has_element?(view, ~s(#order-progress [data-step="ready"][data-state="current"]))
    refute html =~ ~r/>Received — kitchen has it</

    assert {:ok, _} = Orders.complete_order(ready)
    assert has_element?(view, "#order-complete-state")
    assert has_element?(view, ".order-complete-badge", "Order complete")
    assert has_element?(view, "#order-status-message", "Picked up ✓")

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
    refute render(view) =~ "Received — kitchen has it"
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
    assert has_element?(view, "#order-confirm-recap")
    assert has_element?(view, "#order-confirm-recap .order-confirm-recap-total", "₱75")

    assert has_element?(
             view,
             "#order-confirm-lede",
             "Your order is in. Pick it up at the counter when it's ready."
           )

    assert has_element?(view, "#order-confirm-recap", "Pickup at counter")
    refute has_element?(view, "#order-confirm-recap", "Table")
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

    assert has_element?(detail_view, "#order-status-message", "Received — kitchen has it")
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
    refute has_element?(view, "#order-confirm-recap")

    assert {:ok, _} = Orders.mark_paid_from_paymongo(order.number)
    assert has_element?(view, "#order-confirm-title", "Order confirmed")

    assert has_element?(
             view,
             "#order-confirm-lede",
             "Your order is in. Pick it up at the counter when it's ready."
           )

    assert has_element?(view, "#order-confirm-recap .order-confirm-recap-total", "₱100")

    refute has_element?(view, "#order-confirm-title", "Payment processing")
  end

  test "dine-in order confirmation shows table-aware lede and recap", %{conn: conn} do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}],
        %{
          customer_name: "Dine In",
          fulfillment: :dine_in,
          table_number: "12",
          payment_method: :counter
        }
      )

    {:ok, view, _html} = live(conn, ~p"/order/#{order.number}?confirm=1")

    assert has_element?(view, "#order-confirm-title", "Order confirmed")

    assert has_element?(
             view,
             "#order-confirm-lede",
             "Your order is in. Show your order number at the counter — we'll bring it to table 12."
           )

    assert has_element?(view, "#order-confirm-recap", "Dine-in")
    assert has_element?(view, "#order-confirm-recap", "Table")
    assert has_element?(view, "#order-confirm-recap", "12")
    assert has_element?(view, "#order-confirm-recap .order-confirm-recap-total", "₱75")
    refute has_element?(view, "#order-receipt")
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
    {:ok, order} = Orders.mark_paid_from_paymongo(order.number)

    {:ok, view, _html} = live(conn, ~p"/order/#{order.number}?confirm=1")

    assert has_element?(view, "#order-confirm-title", "Order confirmed")
    refute has_element?(view, "#order-confirm-title", "Payment processing")
    assert has_element?(view, "#order-confirm-recap .order-confirm-recap-total", "₱100")
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
    assert has_element?(view, "#order-status-message", "Waiting for payment confirm")
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
    assert has_element?(view, "#order-status-message", "Received — kitchen has it")
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
    refute render(view) =~ "Received — kitchen has it"
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
    assert has_element?(view, "#order-status-message", "Received — kitchen has it")
    assert has_element?(view, "#order-hint", "Pay at counter · show this number.")
    assert has_element?(view, ~s(#order-progress [data-step="received"][aria-current="step"]))
    assert has_element?(view, ~s(#order-progress [data-step="preparing"][data-state="upcoming"]))
    assert has_element?(view, ~s(#order-progress [data-step="ready"][data-state="upcoming"]))
    assert has_element?(view, ~s(#order-progress [data-step="completed"][data-state="upcoming"]))

    assert {:ok, preparing} = Orders.update_status(order, "preparing")
    assert has_element?(view, "#order-status-message", "Preparing your order")
    assert has_element?(view, "#order-hint", "We're preparing it — keep this screen for updates.")
    assert has_element?(view, ~s(#order-progress [data-step="preparing"][aria-current="step"]))

    assert {:ok, _} = Orders.mark_paid(preparing)
    assert {:ok, ready} = Orders.update_status(preparing, "ready")
    assert has_element?(view, "#order-status-message", "Ready — please come to counter")

    assert has_element?(
             view,
             "#order-hint",
             "Show #{order.number} at the counter"
           )

    assert has_element?(view, ~s(#order-progress [data-step="ready"][aria-current="step"]))

    assert {:ok, _} = Orders.complete_order(ready)
    assert has_element?(view, "#order-status-message", "Picked up ✓")
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
    assert has_element?(view, "#order-status-message", "Preparing your order")
    assert has_element?(view, "#order-hint", "We're preparing it — keep this screen for updates.")
    assert has_element?(view, ~s(#order-progress [data-step="preparing"][data-state="current"]))
    assert html =~ "Paid at counter"
    refute has_element?(view, "#order-hint", "Payment is due")
    refute render(view) =~ ~r/claim/i
  end

  test "awaiting_payment order shows counter-scan pay screen without QR image", %{conn: conn} do
    set_payments_mode!("qrph_manual")

    setting = Espreso.BusinessSettings.get()

    setting
    |> Ecto.Changeset.change(%{
      gcash_qrph_path: "/images/gcash-qrph.png",
      maya_qrph_path: "/images/maya-qrph.png"
    })
    |> Espreso.Repo.update!()

    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: nil, quantity: 1, price: Decimal.new("120")}],
        %{
          customer_name: "QR Customer",
          fulfillment: :pickup,
          payment_method: :online,
          online_wallet: :gcash
        }
      )

    {:ok, view, html} = live(conn, ~p"/order/#{order.number}")

    assert has_element?(view, "#order-qrph-payment")
    assert has_element?(view, "#order-qrph-number", order.number)
    assert has_element?(view, "#order-qrph-awaiting", "Waiting")
    assert has_element?(view, "#order-qrph-awaiting", "GCash")
    assert has_element?(view, "#order-qrph-amount", "₱120")
    assert has_element?(view, "#order-qrph-waiting", "Waiting for staff to confirm.")
    assert has_element?(view, ~s(#order-qrph-open-gcash[href="gcash://"]), "Open GCash")
    refute has_element?(view, "#order-qrph-open-maya")
    refute html =~ "Scan the GCash QR at the counter"
    refute html =~ "Open GCash on this phone"
    refute html =~ "I’ve paid"
    refute html =~ "/images/gcash-qrph.png"
    refute html =~ "/images/maya-qrph.png"
    refute html =~ "alt=\"GCash QRPh code\""
    refute has_element?(view, "#order-progress")
    assert has_element?(view, "#order-receipt .order-payment", "Awaiting GCash payment")

    assert {:ok, _} = Orders.mark_paid(order, paid_via: "gcash")
    refute has_element?(view, "#order-qrph-payment")
    assert has_element?(view, "#order-paid-badge", "Paid ✓")
    assert has_element?(view, "#order-status-message", "Preparing your order")
    assert has_element?(view, "#order-progress")
    assert has_element?(view, "#order-receipt .order-payment", "Paid via GCash")
  end

  test "qrph confirm screen is pay-first until staff confirms", %{conn: conn} do
    set_payments_mode!("qrph_manual")

    setting = Espreso.BusinessSettings.get()

    setting
    |> Ecto.Changeset.change(%{
      gcash_qrph_path: "/images/gcash-qrph.png",
      maya_qrph_path: nil
    })
    |> Espreso.Repo.update!()

    {:ok, order} =
      Orders.create_order(
        [%{name: "Americano", size: nil, quantity: 1, price: Decimal.new("95")}],
        %{
          customer_name: "QR Confirm",
          fulfillment: :pickup,
          payment_method: :online,
          online_wallet: :gcash
        }
      )

    {:ok, view, html} = live(conn, ~p"/order/#{order.number}?confirm=1")

    assert has_element?(view, "#order-chrome-title", "Pay at counter")
    refute has_element?(view, ".brune-top")
    assert has_element?(view, "#order-confirm")
    refute has_element?(view, "#order-confirm-title")
    assert has_element?(view, "#order-confirm-qrph")
    assert has_element?(view, "#order-confirm-qrph-number", order.number)
    assert has_element?(view, "#order-confirm-qrph-amount", "₱95")
    assert has_element?(view, ~s(#order-confirm-qrph-open-gcash[href="gcash://"]), "Open GCash")
    assert has_element?(view, "#order-confirm-qrph-waiting", "Waiting for staff to confirm.")
    refute html =~ "scan the QR at the counter"
    refute html =~ "/images/gcash-qrph.png"
    refute has_element?(view, "#order-confirm-title", "Order confirmed")
    refute has_element?(view, "#order-confirm-recap")
    refute has_element?(view, "#order-confirm-number")

    assert {:ok, _} = Orders.mark_paid(order, paid_via: "gcash")
    assert has_element?(view, "#order-confirm-title", "Order confirmed")
    refute has_element?(view, "#order-confirm-qrph")
    assert has_element?(view, "#order-confirm-number", order.number)
    assert has_element?(view, "#order-confirm-recap .order-confirm-recap-total", "₱95")
  end

  defp set_payments_mode!(mode) do
    setting = Espreso.BusinessSettings.get()

    setting
    |> Ecto.Changeset.change(%{payments_mode: mode})
    |> Espreso.Repo.update!()
  end
end
