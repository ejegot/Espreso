defmodule EspresoWeb.StaffCustomerLiveTest do
  use EspresoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Espreso.Accounts
  alias Espreso.Customers
  alias Espreso.Loyalty
  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Orders
  alias Espreso.Repo

  setup %{conn: conn} do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Barista",
        email: "customer-history-barista-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, customer} =
      Customers.find_or_create_by_phone("09174440001", %{name: "Mara"})

    %{conn: conn, barista: barista, customer: customer}
  end

  test "unauthorized visitors are redirected to login", %{conn: conn, customer: customer} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/customers")
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/customers/#{customer.id}")
  end

  test "staff can search by phone and open customer detail", %{
    conn: conn,
    barista: barista,
    customer: customer
  } do
    conn = log_in(conn, barista)
    {:ok, view, html} = live(conn, ~p"/customers")

    assert html =~ "Customers"
    assert has_element?(view, "#customer-search-form")
    assert has_element?(view, "#staff-nav-customers", "Customers")

    {:ok, detail, html} =
      view
      |> form("#customer-search-form", %{phone: "09174440001"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Mara"
    assert has_element?(detail, "#customer-phone", customer.phone_e164)
    assert has_element?(detail, "#customer-points", "0")
    assert has_element?(detail, "#customer-reward-progress")
    assert has_element?(detail, "#customer-orders-empty")
    assert has_element?(detail, "#customer-activity-empty")
    assert has_element?(detail, "#customer-spend-progress", "₱0 / ₱200")
  end

  test "search does not create customers and shows not found", %{
    conn: conn,
    barista: barista
  } do
    before = Repo.aggregate(Espreso.Customers.Customer, :count)

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/customers")

    html =
      view
      |> form("#customer-search-form", %{phone: "09174449999"})
      |> render_submit()

    assert html =~ "No customer found"
    assert Repo.aggregate(Espreso.Customers.Customer, :count) == before
  end

  test "customer detail shows points, reward, orders, and loyalty activity", %{
    conn: conn,
    barista: barista,
    customer: customer
  } do
    {:ok, order} =
      Orders.create_order(
        [%{name: "Latte", size: "12oz", quantity: 1, price: Decimal.new("200")}],
        %{
          customer_name: "Mara",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :paid,
          paid_via: "cash",
          source: :pos,
          customer_id: customer.id,
          skip_authoritative_prices: true
        }
      )

    customer =
      customer
      |> Ecto.Changeset.change(%{points_balance: 10, spend_remainder_centavos: 5_000})
      |> Repo.update!()

    hot = insert_category!("HOT")
    americano = insert_product!(hot, "Americano", [{"8oz", "110"}])

    {:ok, %{order: redeem_order}} =
      Loyalty.redeem_at_pos(customer.id, price_id(americano, "8oz"), %{
        customer_name: "Mara",
        fulfillment: :pickup,
        payment_method: :counter,
        payment_status: :paid,
        paid_via: "cash",
        source: :pos
      })

    customer = Repo.get!(Espreso.Customers.Customer, customer.id)

    {:ok, view, html} = live(log_in(conn, barista), ~p"/customers/#{customer.id}")

    assert has_element?(view, "#customer-name", "Mara")
    assert has_element?(view, "#customer-phone", "+639174440001")
    assert has_element?(view, "#customer-points", Integer.to_string(customer.points_balance))
    assert html =~ "₱50 / ₱200"
    assert has_element?(view, "#customer-order-#{order.id}", order.number)
    assert has_element?(view, "#customer-order-#{redeem_order.id}", redeem_order.number)
    assert has_element?(view, "#customer-activity-list")
    assert html =~ "Earn"
    assert html =~ "Redeem"
    assert html =~ order.number
  end

  test "reward available indicator when balance meets redeem cost", %{
    conn: conn,
    barista: barista,
    customer: customer
  } do
    customer =
      customer
      |> Ecto.Changeset.change(%{points_balance: 10})
      |> Repo.update!()

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/customers/#{customer.id}")

    assert has_element?(view, "#customer-reward-available", "Reward available")
    refute has_element?(view, "#customer-reward-progress")
  end

  test "nil name uses empty-state label", %{conn: conn, barista: barista} do
    {:ok, nameless} = Customers.find_or_create_by_phone("09174440088")

    {:ok, view, _html} = live(log_in(conn, barista), ~p"/customers/#{nameless.id}")

    assert has_element?(view, "#customer-name", "No name on file")
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp price_id(product, size) do
    product = Repo.preload(product, :product_prices)

    product.product_prices
    |> Enum.find(&(to_string(&1.size) == to_string(size)))
    |> Map.fetch!(:id)
  end

  defp insert_category!(name) do
    case Repo.get_by(Category, name: name) do
      %Category{} = category ->
        category

      nil ->
        %Category{}
        |> Category.changeset(%{name: name})
        |> Repo.insert!()
    end
  end

  defp insert_product!(category, name, prices) do
    product =
      %Product{}
      |> Product.changeset(%{
        name: "#{name}-#{System.unique_integer([:positive])}",
        category_id: category.id,
        available: true
      })
      |> Repo.insert!()

    Enum.each(prices, fn {size, price} ->
      %ProductPrice{}
      |> ProductPrice.changeset(%{
        product_id: product.id,
        size: size,
        price: Decimal.new(price)
      })
      |> Repo.insert!()
    end)

    Repo.preload(product, :product_prices)
  end
end
