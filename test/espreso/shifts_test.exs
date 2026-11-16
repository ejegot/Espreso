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
    assert Decimal.equal?(close.opening_cash || Decimal.new("0"), Decimal.new("0"))
    assert Decimal.equal?(close.expected_cash, Decimal.new("120"))
    assert Decimal.equal?(close.variance, Decimal.new("-4.50"))
    assert is_nil(StaffShifts.get_open_shift(manager))
    assert StaffShifts.list_shifts_for_user(manager.id) == []

    assert {:error, :already_closed} =
             Shifts.record_close(manager, %{counted_cash: "200"})

    assert %Shifts.ShiftClose{} = Shifts.get_todays_close()
  end

  test "owner can record_close without StaffShift" do
    owner = owner!()
    assert {:error, :counted_cash_required} = Shifts.record_close(owner, %{})
    assert {:ok, close} = Shifts.record_close(owner, %{counted_cash: "0"})
    assert close.closed_by_user_id == owner.id
    assert Decimal.equal?(close.expected_cash, Decimal.new("0"))
    assert Decimal.equal?(close.variance, Decimal.new("0"))
    assert StaffShifts.list_shifts_for_user(owner.id) == []
  end

  test "barista can close when last active without ending attendance" do
    barista = barista!()
    assert {:ok, open} = StaffShifts.open_shift_for_login(barista)

    assert {:ok, close} = Shifts.record_close(barista, %{counted_cash: "50"})

    assert close.closed_by_user_id == barista.id
    assert StaffShifts.get_open_shift(barista).id == open.id

    closed = Repo.get!(StaffShift, open.id)
    assert is_nil(closed.end_reason)
    assert is_nil(closed.ended_at)
  end

  test "barista cannot close while another StaffShift is open" do
    a = barista!()
    b = barista!()
    assert {:ok, open_a} = StaffShifts.open_shift_for_login(a)
    assert {:ok, open_b} = StaffShifts.open_shift_for_login(b)

    assert {:error, :other_staff_active} = Shifts.record_close(a, %{counted_cash: "10"})
    assert is_nil(Shifts.get_todays_close())
    assert StaffShifts.get_open_shift(a).id == open_a.id
    assert StaffShifts.get_open_shift(b).id == open_b.id

    assert {:ok, _} =
             StaffShifts.close_shift_for_shift_close(
               b.id,
               DateTime.utc_now() |> DateTime.truncate(:second)
             )

    assert {:ok, close} = Shifts.record_close(a, %{counted_cash: "10"})
    assert close.closed_by_user_id == a.id
    assert is_nil(Repo.get!(StaffShift, open_a.id).ended_at)
    assert Repo.get!(StaffShift, open_b.id).end_reason == "shift_close"
  end

  test "barista without open StaffShift cannot close" do
    barista = barista!()
    assert {:error, :not_on_shift} = Shifts.record_close(barista, %{counted_cash: "0"})
    assert is_nil(Shifts.get_todays_close())
  end

  @tag :without_shop_open
  test "record_open is once per active session and snapshots into close" do
    manager = manager!()
    barista = barista!()

    assert {:error, :opening_cash_required} = Shifts.record_open(manager, %{})

    assert {:ok, open} = Shifts.record_open(manager, %{opening_cash: "500"})
    assert open.shop_date == Orders.shop_date_today()
    assert Decimal.equal?(open.opening_cash, Decimal.new("500"))
    assert open.opened_by_user_id == manager.id
    assert {:error, :already_open} = Shifts.record_open(barista, %{opening_cash: "1"})

    {:ok, order} =
      Orders.create_order(lines("120"), %{
        customer_name: "Cash",
        fulfillment: :pickup,
        payment_method: :counter
      })

    {:ok, _} = Orders.mark_paid(order, paid_via: "cash")

    {:ok, _} =
      Espreso.CashOuts.create_cash_out(manager, %{amount: "20", category: "Other"})

    assert {:ok, close} = Shifts.record_close(manager, %{counted_cash: "590"})
    assert Decimal.equal?(close.opening_cash, Decimal.new("500"))
    assert Decimal.equal?(close.expected_cash, Decimal.new("600"))
    assert Decimal.equal?(close.variance, Decimal.new("-10"))
    assert {:ok, next_open} = Shifts.record_open(manager, %{opening_cash: "1"})
    assert next_open.id != open.id
    assert Shifts.get_close_for_date(open.shop_date).id == close.id
  end

  @tag :without_shop_open
  test "selling is blocked until opening cash and after close" do
    manager = manager!()
    lines = lines("75")
    attrs = %{customer_name: "Walk-in", fulfillment: :pickup, payment_method: :counter}

    assert Shifts.shop_day_status() == :not_open
    assert {:error, :shop_not_open} = Orders.create_order(lines, attrs)

    assert {:ok, _} = Shifts.record_open(manager, %{opening_cash: "200"})
    assert Shifts.shop_day_status() == :open

    assert {:ok, order} = Orders.create_order(lines, attrs)
    assert {:ok, unpaid} = Orders.create_order(lines, attrs)
    assert {:ok, _} = Orders.mark_paid(order, paid_via: "cash")

    assert {:ok, _} = Shifts.record_close(manager, %{counted_cash: "275"})
    assert Shifts.shop_day_status() == :closed
    assert {:error, :shop_day_closed} = Orders.create_order(lines, attrs)
    assert {:error, :shop_day_closed} = Orders.mark_paid(unpaid, paid_via: "cash")
    assert {:ok, paid} = Orders.mark_paid(order, paid_via: "cash")
    assert paid.id == order.id
  end

  test "failed already_closed does not close barista StaffShift" do
    manager = manager!()
    barista = barista!()
    assert {:ok, open} = StaffShifts.open_shift_for_login(barista)
    assert {:ok, _} = Shifts.record_close(manager, %{counted_cash: "25"})

    assert {:error, :already_closed} = Shifts.record_close(barista, %{counted_cash: "25"})
    assert StaffShifts.get_open_shift(barista).id == open.id
    assert is_nil(Repo.get!(StaffShift, open.id).ended_at)
  end

  @tag :without_shop_open
  test "an overnight session keeps both sides of midnight in its close and reports" do
    manager = manager!()
    date = Date.add(Orders.shop_date_today(), -2)
    {start_at, _} = Orders.shop_day_bounds_utc(date)
    opened_at = DateTime.add(start_at, 20 * 60 * 60, :second)
    before_midnight = DateTime.add(opened_at, 60 * 60, :second)
    after_midnight = DateTime.add(opened_at, 6 * 60 * 60, :second)

    {:ok, open} = Shifts.record_open(manager, %{opening_cash: "500"})

    open
    |> Ecto.Changeset.change(shop_date: date, opened_at: opened_at)
    |> Repo.update!()

    assert Shifts.shop_day_status() == :open
    assert Shifts.current_session().shop_date == date

    orders =
      for {amount, at} <- [{"100", before_midnight}, {"200", after_midnight}] do
        {:ok, order} =
          Orders.create_order(lines(amount), %{
            customer_name: "Overnight guest",
            fulfillment: :pickup,
            payment_method: :counter
          })

        {:ok, paid} = Orders.mark_paid(order, paid_via: "cash")

        Repo.update_all(from(o in Espreso.Orders.Order, where: o.id == ^paid.id),
          set: [settled_at: at]
        )

        paid
      end

    assert {:ok, cash_out} =
             Espreso.CashOuts.create_cash_out(manager, %{amount: "20", category: "Other"})

    assert {:ok, petty} =
             Espreso.PettyCash.create_entry(manager, %{
               amount: "50",
               category: "Supplies",
               note: "Supplies"
             })

    assert cash_out.shop_date == date
    assert petty.shop_date == date
    assert cash_out.shop_session_id == open.id
    assert petty.shop_session_id == open.id
    assert Decimal.equal?(Orders.todays_paid_breakdown().total, Decimal.new("300"))

    assert {:ok, close} =
             Shifts.record_close(manager, %{counted_cash: "730", petty_cash_counted: "450"})

    assert close.shop_date == date
    assert close.shop_session_id == open.id
    assert close.system_count == 2
    assert Decimal.equal?(close.system_total, Decimal.new("300"))
    assert Decimal.equal?(close.expected_cash, Decimal.new("730"))
    assert Decimal.equal?(close.variance, Decimal.new("0"))
    assert Shifts.shop_day_status() == :closed
    assert {:ok, reported} = Orders.list_paid_orders_for_shop_dates(date, date)
    assert Enum.sort(Enum.map(reported, & &1.id)) == Enum.sort(Enum.map(orders, & &1.id))

    assert {:ok, []} =
             Orders.list_paid_orders_for_shop_dates(Date.add(date, 1), Date.add(date, 1))

    assert {:ok, %{days: [report]}} = Espreso.Reports.CloseExport.pack(date, date)
    assert report.status == "Closed"
    assert Decimal.equal?(report.paid_total, Decimal.new("300"))
    assert Decimal.equal?(report.cash_outs, Decimal.new("20"))
  end

  @tag :without_shop_open
  test "unmatched legacy opening remains incomplete and does not become an active session" do
    manager = manager!()
    today = Orders.shop_date_today()
    opened_at = DateTime.utc_now() |> DateTime.truncate(:second)

    legacy =
      %Shifts.ShopDayOpen{}
      |> Shifts.ShopDayOpen.changeset(%{
        shop_date: today,
        opening_cash: "50",
        opened_at: opened_at,
        opened_by_user_id: manager.id
      })
      |> Repo.insert!()

    assert is_nil(legacy.session_active)
    assert is_nil(Shifts.current_session())
    assert Shifts.shop_day_status() == :not_open
    assert {:ok, current} = Shifts.record_open(manager, %{opening_cash: "100"})
    assert current.id != legacy.id
    assert is_nil(Repo.get!(Shifts.ShopDayOpen, legacy.id).session_active)
    assert {:ok, %{days: days}} = Espreso.Reports.CloseExport.pack(today, today)
    assert Enum.map(days, & &1.status) == ["Incomplete", "Open"]
  end

  test "database rejects a second active session for the same branch" do
    manager = manager!()
    session = Shifts.current_session()

    changeset =
      Shifts.ShopDayOpen.changeset(%Shifts.ShopDayOpen{}, %{
        shop_date: session.shop_date,
        opening_cash: "10",
        opened_at: DateTime.utc_now() |> DateTime.truncate(:second),
        opened_by_user_id: manager.id,
        session_active: true
      })

    assert {:error, changeset} = Repo.insert(changeset, mode: :savepoint)
    assert %{session_active: [_ | _]} = errors_on(changeset)
    assert Shifts.current_session().id == session.id
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

    test "paginates distinct sessions opened on the same business date" do
      manager = manager!()
      attrs = %{customer_name: "Guest", fulfillment: :pickup, payment_method: :counter}
      assert {:ok, order1} = Orders.create_order(lines("20"), attrs)
      assert {:ok, _} = Orders.mark_paid(order1, paid_via: "cash")

      assert {:ok, _} =
               Espreso.CashOuts.create_cash_out(manager, %{amount: "5", category: "Other"})

      assert {:ok, first} = Shifts.record_close(manager, %{counted_cash: "15"})
      assert {:ok, _} = Shifts.record_open(manager, %{opening_cash: "0"})

      assert {:ok, _} =
               Espreso.CashOuts.create_cash_out(manager, %{amount: "2", category: "Other"})

      assert %{days: [%{cash_outs: [past], total: historical_total}]} =
               Espreso.CashOuts.list_cash_out_history()

      assert past.shop_session_id == first.shop_session_id
      assert Decimal.equal?(historical_total, Decimal.new("5"))
      assert {:ok, order2} = Orders.create_order(lines("40"), attrs)
      assert {:ok, _} = Orders.mark_paid(order2, paid_via: "cash")
      assert {:ok, second} = Shifts.record_close(manager, %{counted_cash: "38"})
      assert Decimal.equal?(first.system_total, Decimal.new("20"))
      assert Decimal.equal?(second.system_total, Decimal.new("40"))

      page1 = Shifts.list_close_history(limit: 1)
      page2 = Shifts.list_close_history(limit: 1, cursor: page1.next_cursor)
      assert Enum.map(page1.closes, & &1.id) == [second.id]
      assert Enum.map(page2.closes, & &1.id) == [first.id]

      assert {:ok, %{days: days}} =
               Espreso.Reports.CloseExport.pack(first.shop_date, first.shop_date)

      assert [day1, day2] = days
      assert Decimal.equal?(day1.paid_total, Decimal.new("20"))
      assert Decimal.equal?(day2.paid_total, Decimal.new("40"))
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
      assert page1.next_cursor.date == Enum.at(dates, 1)

      page2 = Shifts.list_close_history(limit: 2, cursor: page1.next_cursor)
      assert Enum.map(page2.closes, & &1.shop_date) == Enum.slice(dates, 2, 2)
      assert page2.has_next_page
      assert page2.next_cursor.date == Enum.at(dates, 3)

      page3 = Shifts.list_close_history(limit: 2, cursor: page2.next_cursor)
      assert Enum.map(page3.closes, & &1.shop_date) == [List.last(dates)]
      refute page3.has_next_page
      assert is_nil(page3.next_cursor)

      all_ids =
        (page1.closes ++ page2.closes ++ page3.closes)
        |> Enum.map(& &1.id)

      assert length(all_ids) == length(Enum.uniq(all_ids))

      # Cursor excludes the already-loaded boundary row.
      refute Enum.any?(page2.closes, &(&1.shop_date == page1.next_cursor.date))
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
