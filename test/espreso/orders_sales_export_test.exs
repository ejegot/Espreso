defmodule Espreso.OrdersSalesExportTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Repo

  import Ecto.Query

  setup do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Export Barista",
        email: "export.barista@test.local",
        password: "password123",
        role: "barista"
      })

    %{barista: barista}
  end

  test "rejects invalid and oversized ranges" do
    assert {:error, :invalid_range} =
             Orders.validate_sales_export_shop_dates(~D[2026-09-10], ~D[2026-09-09])

    assert {:error, :range_too_large} =
             Orders.validate_sales_export_shop_dates(~D[2026-09-01], ~D[2026-10-02])

    assert :ok = Orders.validate_sales_export_shop_dates(~D[2026-09-01], ~D[2026-10-01])
  end

  test "lists paid orders by settled_at Manila shop days and excludes unpaid", %{
    barista: barista
  } do
    # Manila 2026-09-10 10:00 => UTC 2026-09-10 02:00
    paid_in =
      create_paid!(barista,
        settled_at: ~U[2026-09-10 02:00:00Z],
        number_suffix: "IN",
        price: "150",
        paid_via: "gcash",
        payment_intent: "gcash"
      )

    # Settled just before Manila day start (2026-09-10 00:00 Manila = 2026-09-09 16:00 UTC)
    _paid_before =
      create_paid!(barista,
        settled_at: ~U[2026-09-09 15:59:59Z],
        number_suffix: "BEFORE",
        price: "50"
      )

    # inserted_at today-ish but unpaid — must be excluded
    {:ok, unpaid} =
      Orders.create_order([pos_line!("75")], %{
        customer_name: "Unpaid Guest",
        fulfillment: :pickup,
        payment_method: :counter,
        source: :pos
      })

    assert unpaid.payment_status != "paid"

    # Paid but settled outside range end (after 2026-09-10 Manila ends = 2026-09-10 16:00 UTC)
    _paid_after =
      create_paid!(barista,
        settled_at: ~U[2026-09-10 16:00:00Z],
        number_suffix: "AFTER",
        price: "90"
      )

    assert {:ok, orders} =
             Orders.list_paid_orders_for_shop_dates(~D[2026-09-10], ~D[2026-09-10])

    numbers = Enum.map(orders, & &1.number)
    assert paid_in.number in numbers
    refute Enum.any?(numbers, &String.contains?(&1, "BEFORE"))
    refute Enum.any?(numbers, &String.contains?(&1, "AFTER"))
    refute unpaid.number in numbers

    assert Enum.all?(orders, &(&1.payment_status == "paid"))
    assert Enum.all?(orders, &match?(%DateTime{}, &1.settled_at))
    assert hd(orders).items != []
    assert hd(orders).settled_by_user.id == barista.id
  end

  test "inclusive multi-day range uses settled_at bounds", %{barista: barista} do
    day1 =
      create_paid!(barista,
        settled_at: ~U[2026-09-10 02:00:00Z],
        number_suffix: "D1",
        price: "100"
      )

    day2 =
      create_paid!(barista,
        settled_at: ~U[2026-09-11 02:00:00Z],
        number_suffix: "D2",
        price: "200"
      )

    assert {:ok, orders} =
             Orders.list_paid_orders_for_shop_dates(~D[2026-09-10], ~D[2026-09-11])

    numbers = Enum.map(orders, & &1.number)
    assert day1.number in numbers
    assert day2.number in numbers
  end

  defp create_paid!(user, opts) do
    settled_at = Keyword.fetch!(opts, :settled_at)
    price = Keyword.get(opts, :price, "100")
    paid_via = Keyword.get(opts, :paid_via, "cash")
    payment_intent = Keyword.get(opts, :payment_intent)
    suffix = Keyword.get(opts, :number_suffix, "X")

    attrs = %{
      customer_name: "Export Guest #{suffix}",
      fulfillment: :pickup,
      payment_method: :counter,
      payment_status: :paid,
      paid_via: paid_via,
      source: :pos,
      settlement_source: :pos,
      settled_by_user_id: user.id
    }

    attrs =
      if payment_intent,
        do: Map.put(attrs, :payment_intent, payment_intent),
        else: attrs

    {:ok, order} = Orders.create_order([pos_line!(price)], attrs)

    {1, _} =
      Repo.update_all(from(o in Order, where: o.id == ^order.id), set: [settled_at: settled_at])

    Orders.get_transaction(order.id)
  end

  defp pos_line!(amount) do
    category =
      %Espreso.Menu.Category{}
      |> Espreso.Menu.Category.changeset(%{
        name: "ExportCat-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    product =
      %Espreso.Menu.Product{}
      |> Espreso.Menu.Product.changeset(%{
        name: "Espresso-#{System.unique_integer([:positive])}",
        category_id: category.id,
        available: true
      })
      |> Repo.insert!()

    price =
      %Espreso.Menu.ProductPrice{}
      |> Espreso.Menu.ProductPrice.changeset(%{
        product_id: product.id,
        size: "12oz",
        price: Decimal.new(amount)
      })
      |> Repo.insert!()

    %{
      product_id: product.id,
      price_id: price.id,
      name: product.name,
      size: price.size,
      quantity: 1,
      price: price.price
    }
  end
end
