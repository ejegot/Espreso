defmodule EspresoWeb.OrderLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Orders

  test "customer order page updates status and payment without refresh", %{conn: conn} do
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
    assert html =~ "Received"
    assert html =~ "Pay at counter"

    assert {:ok, preparing} = Orders.update_status(order, "preparing")
    assert render(view) =~ "Preparing"

    assert {:ok, _} = Orders.update_status(preparing, "ready")
    assert render(view) =~ "Ready"

    assert {:ok, _} = Orders.mark_paid(preparing)
    assert render(view) =~ "Paid at counter"
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

    {:ok, view, html} = live(conn, ~p"/order/#{order.number}")
    assert html =~ "Received"

    assert {:ok, _} = Orders.cancel_order(order)
    assert render(view) =~ "Cancelled"
  end
end
