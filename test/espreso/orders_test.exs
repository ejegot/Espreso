defmodule Espreso.OrdersTest do
  use Espreso.DataCase, async: true

  import Ecto.Query

  alias Espreso.Orders

  test "create_order assigns CS number and stores lines" do
    lines = [
      %{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")},
      %{name: "Americano", size: "12oz", quantity: 2, price: Decimal.new("120")}
    ]

    assert {:ok, order} =
             Orders.create_order(lines, %{
               customer_name: "Juan",
               fulfillment: :dine_in,
               table_number: "7",
               notes: "less ice",
               payment_method: :counter
             })

    assert order.number =~ ~r/^CS-\d{4,}$/
    assert order.customer_name == "Juan"
    assert order.fulfillment == "dine_in"
    assert order.table_number == "7"
    assert order.payment_method == "counter"
    assert order.payment_status == "unpaid"
    assert order.status == "received"
    assert Decimal.equal?(order.total, Decimal.new("315"))
    assert length(order.items) == 2
  end

  test "create_order requires table for dine-in" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    assert {:error, changeset} =
             Orders.create_order(lines, %{
               customer_name: "Juan",
               fulfillment: :dine_in,
               table_number: "",
               payment_method: :counter
             })

    assert %{table_number: _} = errors_on(changeset)
  end

  test "update_status and mark_paid" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, order} =
      Orders.create_order(lines, %{
        customer_name: "Ana",
        fulfillment: :pickup,
        payment_method: :counter
      })

    assert {:ok, preparing} = Orders.update_status(order, "preparing")
    assert preparing.status == "preparing"

    assert {:ok, paid} = Orders.mark_paid(preparing)
    assert paid.payment_status == "paid"

    assert [%{number: number}] = Orders.list_active_orders()
    assert number == order.number
  end

  test "dashboard_overview returns zeros when empty" do
    assert Orders.dashboard_overview() == %{
             active_count: 0,
             received_count: 0,
             preparing_count: 0,
             unpaid_active_count: 0,
             todays_count: 0
           }
  end

  test "dashboard_overview counts received, preparing, unpaid, and today" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, received} =
      Orders.create_order(lines, %{
        customer_name: "Ria",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, preparing} =
      Orders.create_order(lines, %{
        customer_name: "Pat",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, preparing} = Orders.update_status(preparing, "preparing")

    {:ok, paid_active} =
      Orders.create_order(lines, %{
        customer_name: "Kim",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _paid_active} = Orders.mark_paid(paid_active)

    {:ok, ready} =
      Orders.create_order(lines, %{
        customer_name: "Lex",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, ready} = Orders.update_status(ready, "ready")

    yesterday = DateTime.add(DateTime.utc_now(), -86_400, :second)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^ready.id),
        set: [inserted_at: yesterday, updated_at: yesterday]
      )

    overview = Orders.dashboard_overview()

    assert overview.active_count == 3
    assert overview.received_count == 2
    assert overview.preparing_count == 1
    assert overview.unpaid_active_count == 2
    assert overview.todays_count == 3
    assert received.status == "received"
    assert preparing.status == "preparing"
  end

  test "list_todays_orders returns empty when none today" do
    assert Orders.list_todays_orders() == []
  end

  test "list_todays_orders filters today only, newest first, and respects limit" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    {:ok, older_today} =
      Orders.create_order(lines, %{
        customer_name: "Older",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, newer_today} =
      Orders.create_order(lines, %{
        customer_name: "Newer",
        fulfillment: :dine_in,
        table_number: "3",
        payment_method: :counter
      })

    {:ok, yesterday_order} =
      Orders.create_order(lines, %{
        customer_name: "Yesterday",
        fulfillment: :pickup,
        payment_method: :counter
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    earlier_today = DateTime.add(now, -60, :second)
    yesterday = DateTime.add(now, -86_400, :second)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^older_today.id),
        set: [inserted_at: earlier_today, updated_at: earlier_today]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^newer_today.id),
        set: [inserted_at: now, updated_at: now]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^yesterday_order.id),
        set: [inserted_at: yesterday, updated_at: yesterday]
      )

    todays = Orders.list_todays_orders()
    assert Enum.map(todays, & &1.id) == [newer_today.id, older_today.id]
    refute Enum.any?(todays, &(&1.id == yesterday_order.id))
    refute Enum.any?(todays, &Ecto.assoc_loaded?(&1.items))

    limited = Orders.list_todays_orders(1)
    assert length(limited) == 1
    assert hd(limited).id == newer_today.id
  end
end
