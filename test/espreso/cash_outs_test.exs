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
end
