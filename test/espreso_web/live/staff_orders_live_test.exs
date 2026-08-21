defmodule EspresoWeb.StaffOrdersLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Orders

  test "staff board unlocks with password and shows order", %{conn: conn} do
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
    assert has_element?(view, ".staff-auth-card")

    view
    |> form("form", %{password: "coffeespot"})
    |> render_submit()

    assert has_element?(view, ".staff-order-number", order.number)
    assert has_element?(view, ".staff-order-name", "Mia")

    view
    |> element("button", "Preparing")
    |> render_click()

    assert has_element?(view, ".staff-badge--preparing", "Preparing")
  end
end
