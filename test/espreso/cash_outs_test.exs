defmodule Espreso.CashOutsTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.CashOuts
  alias Espreso.CashOuts.CashOut
  alias Espreso.Orders
  alias Espreso.Orders.Order
  alias Espreso.Repo
  alias Espreso.Shifts
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift

  setup do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Cash Barista",
        email: "cash.barista-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Cash Manager",
        email: "cash.manager-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    {:ok, owner} =
      Accounts.register_user(%{
        name: "Cash Owner",
        email: "cash.owner-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "owner"
      })

    %{barista: barista, manager: manager, owner: owner}
  end

  describe "create_cash_out/2" do
    test "barista with open StaffShift can create Cash Out", %{barista: barista} do
      assert {:ok, shift} = StaffShifts.open_shift_for_login(barista)

      assert {:ok, cash_out} =
               CashOuts.create_cash_out(barista, %{
                 amount: "500",
                 category: "Supplies",
                 note: "Cleaning supplies"
               })

      assert Decimal.equal?(cash_out.amount, Decimal.new("500"))
      assert cash_out.category == "Supplies"
      assert cash_out.note == "Cleaning supplies"
      assert cash_out.created_by_user_id == barista.id
      assert cash_out.staff_shift_id == shift.id
      assert cash_out.status == "recorded"
      assert cash_out.shop_date == Orders.shop_date_today()
      assert %DateTime{} = cash_out.recorded_at
      assert is_nil(cash_out.voided_at)
    end

    test "manager and owner can create without StaffShift", %{manager: manager, owner: owner} do
      assert {:ok, m} =
               CashOuts.create_cash_out(manager, %{amount: "150", category: "Ingredients"})

      assert is_nil(m.staff_shift_id)
      assert m.created_by_user_id == manager.id
      assert StaffShifts.list_shifts_for_user(manager.id) == []

      assert {:ok, o} = CashOuts.create_cash_out(owner, %{amount: "200", category: "Other"})
      assert is_nil(o.staff_shift_id)
      assert StaffShifts.list_shifts_for_user(owner.id) == []
    end

    test "barista without open StaffShift cannot create", %{barista: barista} do
      assert {:error, :not_on_shift} =
               CashOuts.create_cash_out(barista, %{amount: "100", category: "Other"})
    end

    test "closed StaffShift is not accepted for barista", %{barista: barista} do
      assert {:ok, _} = StaffShifts.open_shift_for_login(barista)
      assert {:ok, _} = StaffShifts.close_shift_for_logout(barista.id)

      assert {:error, :not_on_shift} =
               CashOuts.create_cash_out(barista, %{amount: "100", category: "Other"})
    end

    test "rejects zero, negative, and missing category", %{manager: manager} do
      assert {:error, cs} = CashOuts.create_cash_out(manager, %{amount: "0", category: "Other"})
      assert %{amount: _} = errors_on(cs)

      assert {:error, cs} = CashOuts.create_cash_out(manager, %{amount: "-5", category: "Other"})
      assert %{amount: _} = errors_on(cs)

      assert {:error, cs} = CashOuts.create_cash_out(manager, %{amount: "10", category: ""})
      assert %{category: _} = errors_on(cs)
    end

    test "does not create Orders or change paid breakdown / PASS 5C", %{
      barista: barista,
      manager: manager
    } do
      assert {:ok, shift} = StaffShifts.open_shift_for_login(barista)
      before_orders = Repo.aggregate(Order, :count, :id)
      before_breakdown = Orders.todays_paid_breakdown()
      before_sales = Orders.sales_summary_for_staff_shift(Repo.get!(StaffShift, shift.id))

      assert {:ok, _} =
               CashOuts.create_cash_out(manager, %{
                 amount: "800",
                 category: "Ingredients",
                 note: "Milk"
               })

      assert Repo.aggregate(Order, :count, :id) == before_orders
      after_breakdown = Orders.todays_paid_breakdown()
      assert after_breakdown.count == before_breakdown.count
      assert Decimal.equal?(after_breakdown.total, before_breakdown.total)

      after_sales = Orders.sales_summary_for_staff_shift(Repo.get!(StaffShift, shift.id))
      assert after_sales == before_sales
    end

    test "blocked after shop day is sealed", %{manager: manager} do
      assert {:ok, _} = Shifts.record_close(manager, %{})

      assert {:error, :shop_day_closed} =
               CashOuts.create_cash_out(manager, %{amount: "50", category: "Other"})
    end
  end

  describe "list and total" do
    test "lists newest first and totals exclude voided and other days", %{
      manager: manager,
      owner: owner
    } do
      assert {:ok, first} =
               CashOuts.create_cash_out(manager, %{amount: "200", category: "Cleaning"})

      assert {:ok, second} =
               CashOuts.create_cash_out(owner, %{amount: "350", category: "Ingredients"})

      assert {:ok, third} =
               CashOuts.create_cash_out(manager, %{amount: "150", category: "Supplies"})

      today = Orders.shop_date_today()
      list = CashOuts.list_cash_outs_for_shop_date(today)
      assert Enum.map(list, & &1.id) == [third.id, second.id, first.id]

      assert Decimal.equal?(CashOuts.total_for_shop_date(today), Decimal.new("700"))

      assert {:ok, _} = CashOuts.void_cash_out(second, manager, "Entered wrong amount")
      assert Decimal.equal?(CashOuts.total_for_shop_date(today), Decimal.new("350"))

      # Other shop day should not appear in today's list/total
      other =
        %CashOut{}
        |> CashOut.create_changeset(%{
          amount: Decimal.new("999"),
          category: "Other",
          recorded_at: DateTime.utc_now() |> DateTime.truncate(:second),
          shop_date: Date.add(today, -1),
          status: "recorded",
          created_by_user_id: manager.id
        })
        |> Repo.insert!()

      refute Enum.any?(CashOuts.list_cash_outs_for_shop_date(today), &(&1.id == other.id))
      assert Decimal.equal?(CashOuts.total_for_shop_date(today), Decimal.new("350"))
      assert Decimal.equal?(CashOuts.total_for_shop_date(other.shop_date), Decimal.new("999"))
    end
  end

  describe "void_cash_out/3" do
    test "manager voids with reason and preserves original", %{manager: manager} do
      assert {:ok, cash_out} =
               CashOuts.create_cash_out(manager, %{
                 amount: "120",
                 category: "Supplies",
                 note: "Bags"
               })

      assert {:ok, voided} = CashOuts.void_cash_out(cash_out, manager, "Duplicate entry")

      assert voided.status == "voided"
      assert voided.void_reason == "Duplicate entry"
      assert voided.voided_by_user_id == manager.id
      assert %DateTime{} = voided.voided_at
      assert Decimal.equal?(voided.amount, Decimal.new("120"))
      assert voided.category == "Supplies"
      assert voided.note == "Bags"
      assert voided.created_by_user_id == manager.id

      assert {:error, :already_voided} =
               CashOuts.void_cash_out(voided, manager, "Again")
    end

    test "requires void reason and barista cannot void", %{
      barista: barista,
      manager: manager
    } do
      assert {:ok, shift} = StaffShifts.open_shift_for_login(barista)

      assert {:ok, cash_out} =
               CashOuts.create_cash_out(barista, %{amount: "40", category: "Other"})

      assert cash_out.staff_shift_id == shift.id

      assert {:error, :unauthorized} =
               CashOuts.void_cash_out(cash_out, barista, "Oops")

      assert {:error, cs} = CashOuts.void_cash_out(cash_out, manager, "   ")
      assert %{void_reason: _} = errors_on(cs)
    end

    test "void blocked after shop day sealed", %{manager: manager} do
      assert {:ok, cash_out} =
               CashOuts.create_cash_out(manager, %{amount: "75", category: "Cleaning"})

      assert {:ok, _} = Shifts.record_close(manager, %{})

      assert {:error, :shop_day_closed} =
               CashOuts.void_cash_out(cash_out, manager, "Too late")
    end
  end

  test "open shop day remains usable before sealing", %{manager: manager} do
    assert is_nil(Shifts.get_todays_close())

    assert {:ok, _} =
             CashOuts.create_cash_out(manager, %{amount: "10", category: "Other"})

    assert Decimal.equal?(
             CashOuts.total_for_shop_date(Orders.shop_date_today()),
             Decimal.new("10")
           )
  end

  defp insert_day_cash_out!(user, shop_date, attrs \\ %{}) do
    {:ok, cash_out} =
      %CashOut{}
      |> CashOut.create_changeset(%{
        amount: Map.get(attrs, :amount, Decimal.new("100")),
        category: Map.get(attrs, :category, "Other"),
        note: Map.get(attrs, :note),
        recorded_at: DateTime.utc_now() |> DateTime.truncate(:second),
        shop_date: shop_date,
        status: "recorded",
        created_by_user_id: user.id
      })
      |> Repo.insert()

    if Map.get(attrs, :status) == "voided" do
      cash_out
      |> CashOut.void_changeset(%{
        status: "voided",
        voided_at: DateTime.utc_now() |> DateTime.truncate(:second),
        voided_by_user_id: user.id,
        void_reason: Map.get(attrs, :void_reason, "Correction")
      })
      |> Repo.update!()
    else
      cash_out
    end
  end

  describe "list_cash_out_history/1" do
    test "returns empty history when only today has cash outs", %{manager: manager} do
      assert {:ok, _} =
               CashOuts.create_cash_out(manager, %{amount: "25", category: "Other"})

      assert %{days: [], has_next_page: false, next_cursor: nil} =
               CashOuts.list_cash_out_history()
    end

    test "returns previous shop dates newest first and excludes today", %{manager: manager} do
      today = Orders.shop_date_today()
      d1 = Date.add(today, -2)
      d2 = Date.add(today, -1)

      assert {:ok, _} =
               CashOuts.create_cash_out(manager, %{amount: "40", category: "Supplies"})

      insert_day_cash_out!(manager, d1, %{amount: Decimal.new("80"), category: "Cleaning"})
      insert_day_cash_out!(manager, d2, %{amount: Decimal.new("120"), category: "Ingredients"})

      %{days: days, has_next_page: false, next_cursor: nil} = CashOuts.list_cash_out_history()

      assert Enum.map(days, & &1.shop_date) == [d2, d1]
      refute Enum.any?(days, &(&1.shop_date == today))
      assert Decimal.equal?(hd(days).total, Decimal.new("120"))
      assert hd(days).cash_outs |> hd() |> Map.get(:category) == "Ingredients"
    end

    test "includes voided rows and excludes them from day totals", %{manager: manager} do
      today = Orders.shop_date_today()
      day = Date.add(today, -1)

      recorded =
        insert_day_cash_out!(manager, day, %{
          amount: Decimal.new("200"),
          category: "Supplies",
          note: "Bags"
        })

      voided =
        insert_day_cash_out!(manager, day, %{
          amount: Decimal.new("50"),
          category: "Other",
          status: "voided",
          void_reason: "Wrong amount"
        })

      %{days: [entry]} = CashOuts.list_cash_out_history()

      assert entry.shop_date == day

      assert Enum.map(entry.cash_outs, & &1.id) |> Enum.sort() ==
               Enum.sort([recorded.id, voided.id])

      assert Enum.any?(
               entry.cash_outs,
               &(&1.status == "voided" and &1.void_reason == "Wrong amount")
             )

      assert Decimal.equal?(entry.total, Decimal.new("200"))

      assert {:ok, _} =
               CashOuts.void_cash_out(Repo.get!(CashOut, recorded.id), manager, "Also wrong")

      %{days: [after_void]} = CashOuts.list_cash_out_history()
      assert Decimal.equal?(after_void.total, Decimal.new("0"))
      assert Enum.all?(after_void.cash_outs, &(&1.status == "voided"))
    end

    test "keyset pages by shop_date without duplicates", %{manager: manager} do
      today = Orders.shop_date_today()

      dates =
        for offset <- 1..5 do
          date = Date.add(today, -offset)

          insert_day_cash_out!(manager, date, %{
            amount: Decimal.new(Integer.to_string(offset * 10))
          })

          date
        end

      page1 = CashOuts.list_cash_out_history(limit: 2)
      assert Enum.map(page1.days, & &1.shop_date) == Enum.take(dates, 2)
      assert page1.has_next_page
      assert page1.next_cursor == Enum.at(dates, 1)

      page2 = CashOuts.list_cash_out_history(limit: 2, cursor: page1.next_cursor)
      assert Enum.map(page2.days, & &1.shop_date) == Enum.slice(dates, 2, 2)
      assert page2.has_next_page

      page3 = CashOuts.list_cash_out_history(limit: 2, cursor: page2.next_cursor)
      assert Enum.map(page3.days, & &1.shop_date) == [List.last(dates)]
      refute page3.has_next_page
      assert is_nil(page3.next_cursor)

      all_dates =
        (page1.days ++ page2.days ++ page3.days)
        |> Enum.map(& &1.shop_date)

      assert length(all_dates) == length(Enum.uniq(all_dates))
      refute Enum.any?(page2.days, &(&1.shop_date == page1.next_cursor))
    end

    test "page size is respected and clamped", %{manager: manager} do
      today = Orders.shop_date_today()

      for offset <- 1..3 do
        insert_day_cash_out!(manager, Date.add(today, -offset))
      end

      %{days: days} = CashOuts.list_cash_out_history(limit: 1)
      assert length(days) == 1

      %{days: all} = CashOuts.list_cash_out_history(limit: 1000)
      assert length(all) == 3
    end
  end
end
