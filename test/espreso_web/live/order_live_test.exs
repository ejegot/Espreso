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
    assert html =~ "Pay at counter"
    refute html =~ "Status: "

    assert {:ok, preparing} = Orders.update_status(order, "preparing")
    assert has_element?(view, "#order-status-message", "We're preparing your order")
    refute render(view) =~ ~r/Order received/

    assert {:ok, _} = Orders.update_status(preparing, "ready")
    assert has_element?(view, "#order-status-message", "Your order is ready")
    refute render(view) =~ ~r/Order received/

    assert {:ok, _} = Orders.mark_paid(preparing)
    assert render(view) =~ "Paid at counter"
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
    refute html =~ ~r/>Order received</

    assert {:ok, _} = Orders.complete_order(ready)
    assert has_element?(view, "#order-status-message", "Order picked up")
    refute render(view) =~ ~r/Order received/
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

    assert {:ok, _} = Orders.cancel_order(order)
    assert has_element?(view, "#order-status-message", "Order cancelled")
    refute render(view) =~ ~r/Order received/
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

    assert {:ok, preparing} = Orders.update_status(order, "preparing")
    assert has_element?(view, "#order-status-message", "We're preparing your order")

    assert {:ok, ready} = Orders.update_status(preparing, "ready")
    assert has_element?(view, "#order-status-message", "Your order is ready")

    assert {:ok, _} = Orders.complete_order(ready)
    assert has_element?(view, "#order-status-message", "Order picked up")
  end
end
