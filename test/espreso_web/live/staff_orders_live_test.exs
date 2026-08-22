defmodule EspresoWeb.StaffOrdersLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

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

  test "staff board shows order when logged in", %{conn: conn} do
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
    assert has_element?(view, ".staff-order-number", order.number)
    assert has_element?(view, ".staff-order-name", "Mia")

    view
    |> element("button", "Preparing")
    |> render_click()

    assert has_element?(view, ".staff-badge--preparing", "Preparing")
  end
end
