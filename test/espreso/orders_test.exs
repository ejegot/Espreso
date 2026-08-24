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
    assert order.source == "customer"
    assert Decimal.equal?(order.total, Decimal.new("315"))
    assert length(order.items) == 2
  end

  test "create_order accepts source pos" do
    lines = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]

    assert {:ok, order} =
             Orders.create_order(lines, %{
               customer_name: "Walk-in",
               fulfillment: :pickup,
               payment_method: :counter,
               source: :pos
             })

    assert order.source == "pos"
    assert order.fulfillment == "pickup"
    assert order.payment_status == "unpaid"
    assert order.status == "received"
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

  test "sales_overview returns zeros when empty" do
    sales = Orders.sales_overview()
    assert sales.todays_paid_count == 0
    assert Decimal.equal?(sales.todays_paid_total, Decimal.new("0"))
  end

  test "sales_overview includes only today's paid order totals" do
    lines_75 = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]
    lines_120 = [%{name: "Americano", size: "12oz", quantity: 1, price: Decimal.new("120")}]
    lines_200 = [%{name: "Latte", size: "12oz", quantity: 1, price: Decimal.new("200")}]

    {:ok, unpaid_today} =
      Orders.create_order(lines_75, %{
        customer_name: "Unpaid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_a} =
      Orders.create_order(lines_120, %{
        customer_name: "Paid A",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_b} =
      Orders.create_order(lines_200, %{
        customer_name: "Paid B",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, yesterday_paid} =
      Orders.create_order(lines_75, %{
        customer_name: "Yesterday Paid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(paid_a)
    {:ok, _} = Orders.mark_paid(paid_b)
    {:ok, yesterday_paid} = Orders.mark_paid(yesterday_paid)

    yesterday = DateTime.add(DateTime.utc_now(), -86_400, :second) |> DateTime.truncate(:second)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^yesterday_paid.id),
        set: [inserted_at: yesterday, updated_at: yesterday]
      )

    sales = Orders.sales_overview()

    assert sales.todays_paid_count == 2
    assert Decimal.equal?(sales.todays_paid_total, Decimal.new("320"))
    assert unpaid_today.payment_status == "unpaid"
  end

  test "popular_products returns empty when none qualify" do
    assert Orders.popular_products() == []
  end

  test "popular_products ranks paid today by quantity and respects filters/limit" do
    {:ok, unpaid} =
      Orders.create_order(
        [
          %{name: "Espresso", size: nil, quantity: 5, price: Decimal.new("75")}
        ],
        %{customer_name: "Unpaid", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, paid_low} =
      Orders.create_order(
        [
          %{name: "Latte", size: "12oz", quantity: 1, price: Decimal.new("150")},
          %{name: "Americano", size: "8oz", quantity: 2, price: Decimal.new("110")}
        ],
        %{customer_name: "Paid Low", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, paid_high} =
      Orders.create_order(
        [
          %{name: "Americano", size: "12oz", quantity: 3, price: Decimal.new("120")},
          %{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}
        ],
        %{customer_name: "Paid High", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, yesterday_paid} =
      Orders.create_order(
        [%{name: "Mocha", size: "12oz", quantity: 10, price: Decimal.new("160")}],
        %{customer_name: "Yesterday", fulfillment: :pickup, payment_method: :counter}
      )

    {:ok, _} = Orders.mark_paid(paid_low)
    {:ok, _} = Orders.mark_paid(paid_high)
    {:ok, yesterday_paid} = Orders.mark_paid(yesterday_paid)

    yesterday = DateTime.add(DateTime.utc_now(), -86_400, :second) |> DateTime.truncate(:second)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^yesterday_paid.id),
        set: [inserted_at: yesterday, updated_at: yesterday]
      )

    popular = Orders.popular_products()

    assert popular == [
             %{name: "Americano", quantity: 5},
             %{name: "Espresso", quantity: 1},
             %{name: "Latte", quantity: 1}
           ]

    assert unpaid.payment_status == "unpaid"
    refute Enum.any?(popular, &(&1.name == "Mocha"))

    assert Orders.popular_products(1) == [%{name: "Americano", quantity: 5}]
  end

  test "reports_overview returns zeros when empty" do
    reports = Orders.reports_overview()
    assert reports.period_paid_count == 0
    assert reports.period_days == 7
    assert Decimal.equal?(reports.period_paid_total, Decimal.new("0"))
  end

  test "reports_overview includes paid orders across last 7 UTC days only" do
    lines_75 = [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new("75")}]
    lines_120 = [%{name: "Americano", size: "12oz", quantity: 1, price: Decimal.new("120")}]
    lines_200 = [%{name: "Latte", size: "12oz", quantity: 1, price: Decimal.new("200")}]

    {:ok, unpaid_today} =
      Orders.create_order(lines_75, %{
        customer_name: "Unpaid Today",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_today} =
      Orders.create_order(lines_120, %{
        customer_name: "Paid Today",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_mid} =
      Orders.create_order(lines_200, %{
        customer_name: "Paid Mid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_edge} =
      Orders.create_order(lines_75, %{
        customer_name: "Paid Edge",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, paid_old} =
      Orders.create_order(lines_200, %{
        customer_name: "Paid Old",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(paid_today)
    {:ok, paid_mid} = Orders.mark_paid(paid_mid)
    {:ok, paid_edge} = Orders.mark_paid(paid_edge)
    {:ok, paid_old} = Orders.mark_paid(paid_old)

    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")
    mid_window = DateTime.add(today_start, -3, :day)
    edge_window = DateTime.add(today_start, -6, :day)
    too_old = DateTime.add(today_start, -7, :day)

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^paid_mid.id),
        set: [inserted_at: mid_window, updated_at: mid_window]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^paid_edge.id),
        set: [inserted_at: edge_window, updated_at: edge_window]
      )

    {1, _} =
      Espreso.Repo.update_all(
        from(o in Espreso.Orders.Order, where: o.id == ^paid_old.id),
        set: [inserted_at: too_old, updated_at: too_old]
      )

    reports = Orders.reports_overview()

    assert reports.period_days == 7
    assert reports.period_paid_count == 3
    assert Decimal.equal?(reports.period_paid_total, Decimal.new("395"))
    assert unpaid_today.payment_status == "unpaid"
  end
end
