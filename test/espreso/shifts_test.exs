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

  describe "list_close_history/1" do
    alias Espreso.Shifts.ShiftClose

    defp insert_close!(user, shop_date, attrs \\ %{}) do
      closed_at =
        Map.get(attrs, :closed_at) || DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, close} =
        %ShiftClose{}
        |> ShiftClose.changeset(%{
          shop_date: shop_date,
          system_total: Map.get(attrs, :system_total, Decimal.new("100")),
          system_count: Map.get(attrs, :system_count, 1),
          by_via:
            Map.get(attrs, :by_via, %{
              "cash" => %{"total" => "100", "count" => 1}
            }),
          counted_cash: Map.get(attrs, :counted_cash),
          notes: Map.get(attrs, :notes),
          closed_by_user_id: user.id,
          closed_at: closed_at
        })
        |> Repo.insert()

      Repo.preload(close, :closed_by_user)
    end

    test "returns empty history" do
      assert %{closes: [], has_next_page: false, next_cursor: nil} = Shifts.list_close_history()
    end

    test "returns newest shop_date first with sealed snapshot fields" do
      manager = manager!()
      today = Orders.shop_date_today()
      d1 = Date.add(today, -2)
      d2 = Date.add(today, -1)

      older =
        insert_close!(manager, d1, %{
          system_total: Decimal.new("80"),
          system_count: 2,
          by_via: %{"gcash" => %{"total" => "80", "count" => 2}},
          counted_cash: Decimal.new("75"),
          notes: "Short drawer"
        })

      newer =
        insert_close!(manager, d2, %{
          system_total: Decimal.new("150"),
          system_count: 3,
          notes: "Balanced"
        })

      %{closes: closes, has_next_page: false, next_cursor: nil} = Shifts.list_close_history()

      assert Enum.map(closes, & &1.shop_date) == [d2, d1]
      assert hd(closes).id == newer.id
      assert List.last(closes).id == older.id
      assert Decimal.equal?(hd(closes).system_total, Decimal.new("150"))
      assert hd(closes).system_count == 3
      assert hd(closes).notes == "Balanced"
      assert hd(closes).closed_by_user.id == manager.id
      assert Decimal.equal?(List.last(closes).counted_cash, Decimal.new("75"))
      assert List.last(closes).by_via["gcash"]["count"] == 2
    end

    test "keyset pages by shop_date without duplicates" do
      manager = manager!()
      today = Orders.shop_date_today()

      dates =
        for offset <- 1..5 do
          date = Date.add(today, -offset)
          insert_close!(manager, date, %{system_count: offset})
          date
        end

      page1 = Shifts.list_close_history(limit: 2)
      assert Enum.map(page1.closes, & &1.shop_date) == Enum.take(dates, 2)
      assert page1.has_next_page
      assert page1.next_cursor == Enum.at(dates, 1)

      page2 = Shifts.list_close_history(limit: 2, cursor: page1.next_cursor)
      assert Enum.map(page2.closes, & &1.shop_date) == Enum.slice(dates, 2, 2)
      assert page2.has_next_page
      assert page2.next_cursor == Enum.at(dates, 3)

      page3 = Shifts.list_close_history(limit: 2, cursor: page2.next_cursor)
      assert Enum.map(page3.closes, & &1.shop_date) == [List.last(dates)]
      refute page3.has_next_page
      assert is_nil(page3.next_cursor)

      all_ids =
        (page1.closes ++ page2.closes ++ page3.closes)
        |> Enum.map(& &1.id)

      assert length(all_ids) == length(Enum.uniq(all_ids))

      # Cursor excludes the already-loaded boundary row.
      refute Enum.any?(page2.closes, &(&1.shop_date == page1.next_cursor))
    end

    test "page size is respected and clamped" do
      manager = manager!()
      today = Orders.shop_date_today()

      for offset <- 1..3 do
        insert_close!(manager, Date.add(today, -offset))
      end

      %{closes: closes} = Shifts.list_close_history(limit: 1)
      assert length(closes) == 1

      %{closes: all} = Shifts.list_close_history(limit: 1000)
      assert length(all) == 3
    end
  end
end
