defmodule Espreso.ShiftsTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.Orders
  alias Espreso.Repo
  alias Espreso.Shifts
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift

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

  defp owner! do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner-shift-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "owner"
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

  test "manager record_close snapshots totals and does not create StaffShift" do
    manager = manager!()

    {:ok, order} =
      Orders.create_order(lines("120"), %{
        customer_name: "Close",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(order, paid_via: "cash")

    assert is_nil(StaffShifts.get_open_shift(manager))

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
    assert is_nil(StaffShifts.get_open_shift(manager))
    assert StaffShifts.list_shifts_for_user(manager.id) == []

    assert {:error, :already_closed} =
             Shifts.record_close(manager, %{counted_cash: "200"})

    assert %Shifts.ShiftClose{} = Shifts.get_todays_close()
  end

  test "owner can record_close without StaffShift" do
    owner = owner!()
    assert {:ok, close} = Shifts.record_close(owner, %{})
    assert close.closed_by_user_id == owner.id
    assert StaffShifts.list_shifts_for_user(owner.id) == []
  end

  test "barista can close when last active and StaffShift ends with shift_close" do
    barista = barista!()
    assert {:ok, open} = StaffShifts.open_shift_for_login(barista)

    assert {:ok, close} = Shifts.record_close(barista, %{counted_cash: "50"})

    assert close.closed_by_user_id == barista.id
    assert is_nil(StaffShifts.get_open_shift(barista))

    closed = Repo.get!(StaffShift, open.id)
    assert closed.end_reason == "shift_close"
    assert DateTime.compare(closed.ended_at, close.closed_at) == :eq
  end

  test "barista cannot close while another StaffShift is open" do
    a = barista!()
    b = barista!()
    assert {:ok, open_a} = StaffShifts.open_shift_for_login(a)
    assert {:ok, open_b} = StaffShifts.open_shift_for_login(b)

    assert {:error, :other_staff_active} = Shifts.record_close(a, %{})
    assert is_nil(Shifts.get_todays_close())
    assert StaffShifts.get_open_shift(a).id == open_a.id
    assert StaffShifts.get_open_shift(b).id == open_b.id

    assert {:ok, _} = StaffShifts.close_shift_for_logout(b.id)
    assert {:ok, close} = Shifts.record_close(a, %{})
    assert close.closed_by_user_id == a.id
    assert Repo.get!(StaffShift, open_a.id).end_reason == "shift_close"
    assert Repo.get!(StaffShift, open_b.id).end_reason == "logout"
  end

  test "barista without open StaffShift cannot close" do
    barista = barista!()
    assert {:error, :not_on_shift} = Shifts.record_close(barista, %{})
    assert is_nil(Shifts.get_todays_close())
  end

  test "failed already_closed does not close barista StaffShift" do
    manager = manager!()
    barista = barista!()
    assert {:ok, open} = StaffShifts.open_shift_for_login(barista)
    assert {:ok, _} = Shifts.record_close(manager, %{})

    assert {:error, :already_closed} = Shifts.record_close(barista, %{})
    assert StaffShifts.get_open_shift(barista).id == open.id
    assert is_nil(Repo.get!(StaffShift, open.id).ended_at)
  end
end
