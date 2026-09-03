defmodule EspresoWeb.StaffPosLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Orders
  alias Espreso.Repo
  alias EspresoWeb.StaffPosLive

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
    assert has_element?(view, ".staff-shell-title", "POS")
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

    [order] = Orders.list_active_orders()
    assert order.number =~ Orders.order_number_pattern()
    assert html =~ order.number
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

  test "Place Order creates exactly one order; repeated place_order while placing is ignored", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()

    view |> element("#pos-place-order") |> render_click()
    # Second click after success: confirmation is showing (no place button / cart cleared).
    view |> render_click("place_order", %{})

    assert length(Orders.list_active_orders()) == 1
    assert has_element?(view, "#pos-confirmation")
  end

  test "repeated place_order is ignored while placing_order? is already true", %{
    espresso: espresso
  } do
    price = hd(espresso.product_prices)

    cart = [
      %{
        key: "#{espresso.id}-#{price.id}",
        name: espresso.name,
        size: price.size,
        quantity: 1,
        price: price.price
      }
    ]

    socket =
      place_order_socket(%{
        placing_order?: true,
        cart: cart,
        customer_name: "Walk-in",
        payment_choice: :unpaid
      })

    assert {:noreply, next} = StaffPosLive.handle_event("place_order", %{}, socket)
    assert next.assigns.placing_order? == true
    assert next.assigns.cart == cart
    assert Orders.list_active_orders() == []
  end

  test "placing_order? resets after successful creation", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-place-order") |> render_click()

    assert has_element?(view, "#pos-confirmation")

    view |> element("#pos-new-order") |> render_click()
    view |> element("#pos-product-#{espresso.id}") |> render_click()

    refute has_element?(view, "#pos-place-order[disabled]")
    view |> element("#pos-place-order") |> render_click()

    assert length(Orders.list_active_orders()) == 2
    assert has_element?(view, "#pos-confirmation")
  end

  test "placing_order? resets after create_order error", %{espresso: espresso} do
    price = hd(espresso.product_prices)

    cart = [
      %{
        key: "#{espresso.id}-#{price.id}",
        product_id: espresso.id,
        name: espresso.name,
        size: price.size,
        quantity: 1,
        price: price.price
      }
    ]

    socket =
      place_order_socket(%{
        placing_order?: false,
        cart: cart,
        # Too short for Order.changeset customer_name validation
        customer_name: "A",
        payment_choice: :unpaid
      })

    assert {:noreply, next} = StaffPosLive.handle_event("place_order", %{}, socket)
    assert next.assigns.placing_order? == false
    assert next.assigns.error == "Enter a customer name (at least 2 characters)."
    assert next.assigns.cart == cart
    assert Orders.list_active_orders() == []
  end

  test "POS saves custom customer name and notes on placed order", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view
    |> element("#pos-customer-name")
    |> render_change(%{"customer_name" => "Maria"})

    view
    |> element("#pos-notes")
    |> render_change(%{"notes" => "Less ice"})

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-place-order") |> render_click()

    assert has_element?(view, "#pos-confirmation", "Maria")
    assert has_element?(view, "#pos-confirmation", "Less ice")

    [order] = Orders.list_active_orders()
    assert order.customer_name == "Maria"
    assert order.notes == "Less ice"
  end

  test "empty notes are not stored on the order", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-place-order") |> render_click()

    [order] = Orders.list_active_orders()
    assert order.notes == nil
  end

  test "short customer name shows validation error before placing", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")

    view
    |> element("#pos-customer-name")
    |> render_change(%{"customer_name" => "A"})

    view |> element("#pos-product-#{espresso.id}") |> render_click()
    view |> element("#pos-place-order") |> render_click()

    assert has_element?(view, "#pos-error", "Enter a customer name")
    refute has_element?(view, "#pos-confirmation")
    assert Orders.list_active_orders() == []
  end

  test "unavailable product at place shows error, keeps cart, and resets placing_order?", %{
    conn: conn,
    barista: barista,
    espresso: espresso
  } do
    {:ok, view, _html} = live(log_in(conn, barista), ~p"/pos")
    view |> element("#pos-product-#{espresso.id}") |> render_click()

    espresso
    |> Product.changeset(%{available: false})
    |> Repo.update!()

    view |> element("#pos-place-order") |> render_click()

    assert has_element?(view, "#pos-error", "Espresso is no longer available")
    assert has_element?(view, "#pos-cart-lines", "Espresso")
    refute has_element?(view, "#pos-confirmation")
    assert Orders.list_active_orders() == []

    Repo.get!(Product, espresso.id)
    |> Product.changeset(%{available: true})
    |> Repo.update!()

    view |> element("#pos-place-order") |> render_click()

    assert has_element?(view, "#pos-confirmation")
    assert length(Orders.list_active_orders()) == 1
  end

  test "staff home hub links barista to Orders and POS", %{
    conn: conn,
    barista: barista
  } do
    {:ok, home, html} = live(log_in(conn, barista), ~p"/staff")
    assert html =~ "Shift desk"
    assert has_element?(home, "#staff-home-orders", "Orders")
    assert has_element?(home, "#staff-home-pos", "POS")
    assert has_element?(home, "#staff-home-unpaid", "Unpaid")
    assert has_element?(home, "#staff-notif-toggle")
    assert has_element?(home, "#staff-home-today-barista")

    {:ok, view, html} = live(log_in(conn, barista), ~p"/orders")
    assert has_element?(view, "#staff-nav-pos", "POS")
    refute html =~ "Coming next"
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp place_order_socket(assigns) do
    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(
      Map.merge(
        %{
          categories: [],
          selected_category: nil,
          size_picker: nil,
          last_order: nil,
          error: nil,
          notes: ""
        },
        assigns
      )
    )
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

  test "POS search filters products and Process Order label is present", %{
    conn: conn,
    barista: barista,
    espresso: espresso,
    americano: americano
  } do
    {:ok, view, html} = live(log_in(conn, barista), ~p"/pos")

    assert html =~ "Choose menu"
    assert has_element?(view, "#pos-place-order", "Process Order")
    assert has_element?(view, "#pos-search-input")
    assert has_element?(view, "#pos-product-#{espresso.id}")
    assert has_element?(view, "#pos-product-#{americano.id}")

    view
    |> form("#pos-search", %{q: "Amer"})
    |> render_change()

    assert has_element?(view, "#pos-product-#{americano.id}")
    refute has_element?(view, "#pos-product-#{espresso.id}")

    view |> element("#pos-search-clear") |> render_click()
    assert has_element?(view, "#pos-product-#{espresso.id}")
  end
end
