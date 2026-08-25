defmodule EspresoWeb.StaffPosLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Orders
  alias Espreso.Repo

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner.pos@test.local",
        password: "password123",
        role: "owner"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Manager",
        email: "manager.pos@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, barista} =
      Accounts.register_user(%{
        name: "Staff",
        email: "staff.pos@test.local",
        password: "password123",
        role: "barista"
      })

    hot = insert_category!("HOT")
    cold = insert_category!("COLD")

    espresso = insert_product!(hot, "Espresso", true, [{nil, "75"}])
    americano = insert_product!(hot, "Americano", true, [{"8oz", "110"}, {"12oz", "120"}])
    _unavailable = insert_product!(hot, "Hidden Mocha", false, [{nil, "160"}])
    iced = insert_product!(cold, "Iced Latte", true, [{nil, "150"}])

    %{
      owner: owner,
      manager: manager,
      barista: barista,
      espresso: espresso,
      americano: americano,
      iced: iced
    }
  end

  test "authorized staff can open POS; guests cannot", %{conn: conn, barista: barista} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/pos")

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    assert has_element?(view, ".staff-orders-title", "POS")
    assert has_element?(view, "#pos-catalog")
    assert has_element?(view, "#pos-ticket")
    refute render(view) =~ "Coming soon"
  end

  test "manager and owner can open POS", %{conn: conn, manager: manager, owner: owner} do
    {:ok, manager_view, _html} = live(log_in(conn, manager), ~p"/pos")
    assert has_element?(manager_view, "#pos-place-order")

    {:ok, owner_view, _html} = live(log_in(conn, owner), ~p"/pos")
    assert has_element?(owner_view, "#pos-place-order")
  end

  test "POS shows available products and hides unavailable", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, html} = live(log_in(conn, barista), ~p"/pos")

    assert has_element?(view, "#pos-product-#{espresso.id}", "Espresso")
    assert html =~ "Espresso"
    refute html =~ "Hidden Mocha"
    assert has_element?(view, "#pos-category-HOT")
    assert has_element?(view, "#pos-category-COLD")
  end

  test "category selection switches product list", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    iced: iced
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    assert has_element?(view, "#pos-product-#{espresso.id}")
    refute has_element?(view, "#pos-product-#{iced.id}")

    view |> element("#pos-category-COLD") |> render_click()

    assert has_element?(view, "#pos-product-#{iced.id}", "Iced Latte")
    refute has_element?(view, "#pos-product-#{espresso.id}")
  end

  test "add, increase, decrease, and remove cart lines", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view |> element("#pos-product-#{espresso.id}") |> render_click()

    assert has_element?(view, "#pos-cart-lines", "Espresso")
    assert has_element?(view, "#pos-total", "₱75")

    key = "#{espresso.id}-#{hd(espresso.product_prices).id}"

    view |> element(~s(button[phx-click="inc"][phx-value-key="#{key}"])) |> render_click()
    assert has_element?(view, "#pos-line-#{key}", "2")
    assert has_element?(view, "#pos-total", "₱150")

    view |> element(~s(button[phx-click="dec"][phx-value-key="#{key}"])) |> render_click()
    assert has_element?(view, "#pos-total", "₱75")

    view |> element(~s(button[phx-click="remove"][phx-value-key="#{key}"])) |> render_click()
    assert has_element?(view, "#pos-cart-empty")
  end

  test "multi-price product requires size selection", %{
    conn: conn,
    barista: barista,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view |> element("#pos-product-#{americano.id}") |> render_click()
    assert has_element?(view, "#pos-size-picker", "Americano")

    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    view |> element("#pos-size-#{price_12.id}") |> render_click()

    assert has_element?(view, "#pos-cart-lines", "Americano")
    assert has_element?(view, "#pos-cart-lines", "12oz")
    assert has_element?(view, "#pos-total", "₱120")
  end

  test "empty cart cannot be submitted", %{conn: conn, barista: barista} do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    assert has_element?(view, "#pos-place-order[disabled]")
    refute has_element?(view, "#pos-confirmation")
  end

  test "placing order creates POS order with items, total, source, and confirmation", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-product-#{americano.id}") |> render_click()

    price_12 = Enum.find(americano.product_prices, &(&1.size == "12oz"))
    view |> element("#pos-size-#{price_12.id}") |> render_click()

    espresso_key = "#{espresso.id}-#{hd(espresso.product_prices).id}"

    view
    |> element(~s(button[phx-click="inc"][phx-value-key="#{espresso_key}"]))
    |> render_click()

    view |> element("#pos-place-order") |> render_click()

    assert has_element?(view, "#pos-confirmation")
    assert has_element?(view, "#pos-confirmation", "Received")
    assert has_element?(view, "#pos-confirmation", "Pay at counter")
    assert has_element?(view, "#pos-confirmation a[href='/orders']", "View Orders")
    assert has_element?(view, "#pos-new-order", "New Order")
    refute has_element?(view, "#pos-place-order")

    html = render(view)
    assert html =~ ~r/CS-\d+/

    [order] = Orders.list_active_orders()
    assert order.source == "pos"
    assert order.customer_name == "Walk-in"
    assert order.fulfillment == "pickup"
    assert order.payment_method == "counter"
    assert order.payment_status == "unpaid"
    assert order.status == "received"
    assert Decimal.equal?(order.total, Decimal.new("270"))
    assert length(order.items) == 2

    names = Enum.map(order.items, & &1.name) |> Enum.sort()
    assert names == ["Americano", "Espresso"]

    view |> element("#pos-new-order") |> render_click()

    assert has_element?(view, "#pos-cart-empty")
    assert has_element?(view, "#pos-place-order[disabled]")
    assert has_element?(view, "#pos-payment-unpaid.is-active", "Unpaid")
    refute has_element?(view, "#pos-confirmation")
  end

  test "POS defaults to unpaid and can place paid counter order", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    assert has_element?(view, "#pos-payment-unpaid.is-active", "Unpaid")
    refute has_element?(view, "#pos-payment-paid.is-active")

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-payment-paid") |> render_click()

    assert has_element?(view, "#pos-payment-paid.is-active", "Paid")

    view |> element("#pos-place-order") |> render_click()

    assert has_element?(view, "#pos-confirmation", "Paid at counter")

    [order] = Orders.list_active_orders()
    assert order.source == "pos"
    assert order.payment_method == "counter"
    assert order.payment_status == "paid"
    assert order.status == "received"
  end

  test "staff home POS card is ready (not Soon)", %{conn: conn, barista: barista} do
    {:ok, view, html} = live(log_in(conn, barista), ~p"/staff")
    assert has_element?(view, "a[href='/pos']", "POS")
    refute html =~ "Soon"
    refute html =~ "Coming next"
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp insert_category!(name) do
    %Category{} |> Category.changeset(%{name: name}) |> Repo.insert!()
  end

  defp insert_product!(category, name, available, prices) do
    product =
      %Product{}
      |> Product.changeset(%{name: name, category_id: category.id, available: available})
      |> Repo.insert!()

    prices =
      Enum.map(prices, fn {size, price} ->
        %ProductPrice{}
        |> ProductPrice.changeset(%{
          product_id: product.id,
          size: size,
          price: Decimal.new(price)
        })
        |> Repo.insert!()
      end)

    %{product | product_prices: prices}
  end
end
