defmodule EspresoWeb.Api.V1.OrderControllerTest do
  use EspresoWeb.ConnCase, async: true

  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Orders
  alias Espreso.Repo

  setup do
    hot = insert_category!("HOT")
    product = insert_product!(hot, "Espresso", true, [{nil, "75"}])
    [price] = product.product_prices

    barista = register_staff!("Order API Barista", "orders.barista@coffeespot.local", "barista")
    owner = register_staff!("Order API Owner", "orders.owner@coffeespot.local", "owner")

    %{product: product, price: price, barista: barista, owner: owner}
  end

  test "GET /orders requires authentication", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/orders")
    assert json_response(conn, 401) == %{"error" => "unauthorized"}
  end

  test "barista can list, show, update, and mark paid", %{
    conn: conn,
    barista: barista,
    product: product,
    price: price
  } do
    {:ok, order} =
      Orders.create_order(
        [%{product_id: product.id, name: product.name, size: nil, quantity: 1, price: price.price}],
        %{customer_name: "API Guest", fulfillment: :pickup, payment_method: :counter}
      )

    conn = json_auth_conn(conn, barista) |> get(~p"/api/v1/orders")
    assert %{"orders" => orders} = json_response(conn, 200)
    assert Enum.any?(orders, &(&1["id"] == order.id))

    conn = build_conn() |> json_auth_conn(barista) |> get(~p"/api/v1/orders/#{order.id}")
    assert %{"order" => %{"number" => number}} = json_response(conn, 200)
    assert number == order.number

    conn =
      build_conn()
      |> json_auth_conn(barista)
      |> patch(~p"/api/v1/orders/#{order.id}/mark_paid", %{paid_via: "cash"})

    assert %{"order" => %{"payment_status" => "paid", "paid_via" => "cash"}} =
             json_response(conn, 200)
  end

  test "POST /orders creates a walk-in POS order", %{
    conn: conn,
    barista: barista,
    product: product,
    price: price
  } do
    conn =
      conn
      |> json_auth_conn(barista)
      |> post(~p"/api/v1/orders", %{
        customer_name: "Walk-in API",
        payment_status: "unpaid",
        lines: [%{product_id: product.id, price_id: price.id, quantity: 1}]
      })

    assert %{"order" => %{"customer_name" => "Walk-in API", "source" => "pos"}} =
             json_response(conn, 201)
  end

  test "settings business is readable by any authenticated staff", %{conn: conn, barista: barista} do
    conn = json_auth_conn(conn, barista) |> get(~p"/api/v1/settings/business")

    assert %{"settings" => %{"business_name" => _, "payments_mode" => "counter_only"}} =
             json_response(conn, 200)
  end

  test "menu requires view_menu permission", %{conn: conn, barista: barista} do
    conn = json_auth_conn(conn, barista) |> get(~p"/api/v1/menu")
    assert %{"menu" => menu} = json_response(conn, 200)
    assert is_list(menu)
  end

  defp insert_category!(name) do
    %Category{} |> Category.changeset(%{name: name}) |> Repo.insert!()
  end

  defp insert_product!(category, name, available, prices) do
    product =
      %Product{}
      |> Product.changeset(%{name: name, category_id: category.id, available: available})
      |> Repo.insert!()

    product =
      Enum.reduce(prices, product, fn {size, price}, acc ->
        %ProductPrice{}
        |> ProductPrice.changeset(%{product_id: acc.id, size: size, price: Decimal.new(price)})
        |> Repo.insert!()

        Repo.preload(acc, :product_prices, force: true)
      end)

    Repo.preload(product, :product_prices)
  end
end
