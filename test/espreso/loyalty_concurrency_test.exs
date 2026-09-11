defmodule Espreso.LoyaltyConcurrencyTest do
  use Espreso.DataCase, async: false

  import Ecto.Query

  alias Espreso.Accounts
  alias Espreso.Customers
  alias Espreso.Loyalty
  alias Espreso.Loyalty.LedgerEntry
  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Orders
  alias Espreso.Repo

  test "concurrent redeem cannot double-spend the same 10 points" do
    {:ok, customer} = Customers.find_or_create_by_phone("09173330001", %{name: "Race"})

    customer =
      customer
      |> Ecto.Changeset.change(%{points_balance: 10})
      |> Repo.update!()

    hot = insert_category!("HOT")
    product = insert_product!(hot, "Race Americano", [{"8oz", "110"}])
    price_id = hd(product.product_prices).id

    {:ok, staff} =
      Accounts.register_user(%{
        name: "Race Staff",
        email: "loyalty.race-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    attrs = %{
      customer_name: "Race",
      fulfillment: :pickup,
      payment_method: :counter,
      payment_status: :paid,
      paid_via: "cash",
      source: :pos,
      settled_by_user_id: staff.id,
      settlement_source: :pos
    }

    parent = self()

    task_a =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
        Loyalty.redeem_at_pos(customer.id, price_id, attrs)
      end)

    task_b =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
        Loyalty.redeem_at_pos(customer.id, price_id, attrs)
      end)

    results = [Task.await(task_a, 5_000), Task.await(task_b, 5_000)]
    oks = Enum.filter(results, &match?({:ok, _}, &1))
    errors = Enum.filter(results, &match?({:error, _}, &1))

    assert length(oks) == 1
    assert length(errors) == 1
    assert hd(errors) == {:error, :insufficient_points}

    customer = Repo.get!(Espreso.Customers.Customer, customer.id)
    assert customer.points_balance == 0

    redeems =
      LedgerEntry
      |> where([e], e.customer_id == ^customer.id and e.kind == "redeem")
      |> Repo.all()

    assert length(redeems) == 1
  end

  test "concurrent earn for same order awards once" do
    {:ok, customer} = Customers.find_or_create_by_phone("09173330002")

    {:ok, order} =
      Orders.create_order(
        [%{name: "Item", size: nil, quantity: 1, price: Decimal.new("200")}],
        %{
          customer_name: "Race",
          fulfillment: :pickup,
          payment_method: :counter,
          payment_status: :paid,
          paid_via: "cash",
          source: :pos,
          customer_id: customer.id,
          skip_authoritative_prices: true,
          skip_loyalty_earn: true
        }
      )

    parent = self()

    task_a =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
        Loyalty.earn_for_paid_order(order)
      end)

    task_b =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
        Loyalty.earn_for_paid_order(order)
      end)

    _ = [Task.await(task_a, 5_000), Task.await(task_b, 5_000)]

    customer = Repo.get!(Espreso.Customers.Customer, customer.id)
    assert customer.points_balance == 1

    earns =
      LedgerEntry
      |> where([e], e.order_id == ^order.id and e.kind == "earn")
      |> Repo.all()

    assert length(earns) == 1
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
