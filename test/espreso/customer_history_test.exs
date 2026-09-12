defmodule Espreso.CustomerHistoryTest do
  use Espreso.DataCase, async: true

  alias Espreso.Customers
  alias Espreso.Loyalty
  alias Espreso.Loyalty.LedgerEntry
  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Orders
  alias Espreso.Repo

  setup do
    {:ok, customer} = Customers.find_or_create_by_phone("09173330001", %{name: "History"})
    {:ok, other} = Customers.find_or_create_by_phone("09173330002", %{name: "Other"})

    %{customer: customer, other: other}
  end

  describe "Orders.list_orders_for_customer/2" do
    test "returns only matching customer_id orders, newest first", %{
      customer: customer,
      other: other
    } do
      {:ok, older} = create_paid_order(customer, "100", inserted_offset: -120)
      {:ok, newer} = create_paid_order(customer, "150", inserted_offset: -30)
      {:ok, _anonymous} = create_anonymous_order("Walk-in", "80")
      {:ok, _other} = create_paid_order(other, "90")

      orders = Orders.list_orders_for_customer(customer.id)

      assert Enum.map(orders, & &1.id) == [newer.id, older.id]
      assert Enum.all?(orders, &(&1.customer_id == customer.id))
      refute Enum.any?(orders, &is_nil(&1.customer_id))
    end

    test "does not return name-only orders that share a customer name", %{customer: customer} do
      {:ok, linked} = create_paid_order(customer, "120")
      {:ok, _name_only} = create_anonymous_order(customer.name, "99")

      orders = Orders.list_orders_for_customer(customer.id)

      assert Enum.map(orders, & &1.id) == [linked.id]
    end
  end

  describe "Loyalty.list_activity_for_customer/2" do
    test "returns earn and redeem activity for the customer, newest first", %{
      customer: customer,
      other: other
    } do
      {:ok, earn_order} = create_paid_order(customer, "200")
      customer = Repo.get!(Espreso.Customers.Customer, customer.id)
      assert customer.points_balance == 1

      set_points!(customer, 10)
      hot = insert_category!("HOT")
      americano = insert_product!(hot, "Americano", [{"8oz", "110"}, {"12oz", "120"}])

      {:ok, %{order: redeem_order}} =
        Loyalty.redeem_at_pos(customer.id, price_id(americano, "8oz"), %{
          customer_name: "History",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :paid,
          paid_via: "cash",
          source: :pos
        })

      {:ok, _} = create_paid_order(other, "200")

      activity = Loyalty.list_activity_for_customer(customer.id)
      other_activity = Loyalty.list_activity_for_customer(other.id)

      assert Enum.all?(activity, &(&1.customer_id == customer.id))
      assert Enum.all?(other_activity, &(&1.customer_id == other.id))
      assert Enum.any?(activity, &(&1.kind == "earn" and &1.order_id == earn_order.id))
      assert Enum.any?(activity, &(&1.kind == "redeem" and &1.order_id == redeem_order.id))

      redeem_entry = Enum.find(activity, &(&1.kind == "redeem"))
      assert redeem_entry.order.number == redeem_order.number
      assert %LedgerEntry{} = redeem_entry

      ids = Enum.map(activity, & &1.id)
      assert ids == Enum.sort(ids, :desc)

      assert Enum.map(activity, & &1.inserted_at) ==
               activity |> Enum.map(& &1.inserted_at) |> Enum.sort({:desc, DateTime})
    end
  end

  defp create_paid_order(customer, amount, opts \\ []) do
    offset = Keyword.get(opts, :inserted_offset, 0)

    {:ok, order} =
      Orders.create_order(
        [%{name: "Item", size: nil, quantity: 1, price: Decimal.new(amount)}],
        %{
          customer_name: customer.name || "Loyal",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :paid,
          paid_via: "cash",
          source: :pos,
          customer_id: customer.id,
          skip_authoritative_prices: true
        }
      )

    if offset != 0 do
      at =
        order.inserted_at
        |> DateTime.add(offset, :second)
        |> DateTime.truncate(:second)

      order
      |> Ecto.Changeset.change(%{inserted_at: at, settled_at: at})
      |> Repo.update()
    else
      {:ok, order}
    end
  end

  defp create_anonymous_order(name, amount) do
    Orders.create_order(
      [%{name: "Item", size: nil, quantity: 1, price: Decimal.new(amount)}],
      %{
        customer_name: name,
        fulfillment: :pickup,
        payment_method: :counter,
        payment_status: :paid,
        paid_via: "cash",
        source: :pos,
        skip_authoritative_prices: true
      }
    )
  end

  defp set_points!(customer, points) do
    customer
    |> Ecto.Changeset.change(%{points_balance: points})
    |> Repo.update!()
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
