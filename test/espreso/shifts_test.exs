defmodule Espreso.ShiftsTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.Orders
  alias Espreso.Shifts

  defp lines(amount) do
    [%{name: "Espresso", size: nil, quantity: 1, price: Decimal.new(amount)}]
  end

  defp manager! do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Manager",
        email: "manager-shift-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    user
  end

  defp barista! do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Barista",
        email: "barista-shift-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    user
  end

  test "todays_paid_breakdown groups paid orders by paid_via" do
    {:ok, cash} =
      Orders.create_order(lines("100"), %{
        customer_name: "Cash",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, gcash} =
      Orders.create_order(lines("150"), %{
        customer_name: "GCash",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, unpaid} =
      Orders.create_order(lines("200"), %{
        customer_name: "Unpaid",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(cash, paid_via: "cash")
    {:ok, _} = Orders.mark_paid(gcash, paid_via: "gcash")

    breakdown = Orders.todays_paid_breakdown()

    assert breakdown.count == 2
    assert Decimal.equal?(breakdown.total, Decimal.new("250"))
    assert breakdown.by_via["cash"].count == 1
    assert Decimal.equal?(breakdown.by_via["cash"].total, Decimal.new("100"))
    assert breakdown.by_via["gcash"].count == 1
    assert Decimal.equal?(breakdown.by_via["gcash"].total, Decimal.new("150"))
    assert breakdown.by_via["maya"].count == 0
    assert unpaid.payment_status == "unpaid"
    assert breakdown.shop_date == Orders.shop_date_today()
  end

  test "record_close snapshots totals and blocks barista" do
    manager = manager!()
    barista = barista!()

    {:ok, order} =
      Orders.create_order(lines("120"), %{
        customer_name: "Close",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(order, paid_via: "cash")

    assert {:error, :unauthorized} = Shifts.record_close(barista, %{counted_cash: "120"})

    assert {:ok, close} =
             Shifts.record_close(manager, %{
               counted_cash: "115.50",
               notes: "Drawer short"
             })

    assert close.shop_date == Orders.shop_date_today()
    assert close.system_count == 1
    assert Decimal.equal?(close.system_total, Decimal.new("120"))
    assert Decimal.equal?(close.counted_cash, Decimal.new("115.50"))
    assert close.notes == "Drawer short"
    assert close.closed_by_user_id == manager.id
    assert close.by_via["cash"]["count"] == 1

    assert {:error, :already_closed} =
             Shifts.record_close(manager, %{counted_cash: "200"})

    assert %Shifts.ShiftClose{} = Shifts.get_todays_close()
  end
end
