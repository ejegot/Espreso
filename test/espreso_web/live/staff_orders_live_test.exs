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

    view
    |> element("button", "Mark paid")
    |> render_click()

    refute has_element?(view, "#cancel-order-#{order.id}")
    assert has_element?(view, ".staff-badge--pay-paid")
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

    view
    |> element("button", "Ready")
    |> render_click()

    refute has_element?(view, "#cancel-order-#{order.id}")
    assert has_element?(view, ".staff-order-number", order.number)
  end
end
