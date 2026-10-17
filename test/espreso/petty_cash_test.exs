defmodule Espreso.PettyCashTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.Orders
  alias Espreso.PettyCash
  alias Espreso.Reports.CloseExport
  alias Espreso.Shifts
  alias Espreso.StaffShifts

  defp manager! do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Petty Cash Manager",
        email: "petty-manager-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "manager"
      })

    user
  end

  defp barista! do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Petty Cash Barista",
        email: "petty-barista-#{System.unique_integer([:positive])}@test.local",
        password: "password123",
        role: "barista"
      })

    user
  end

  test "records expenses separately from Cash Out and limits purchases to the remaining float" do
    manager = manager!()

    assert {:ok, entry} =
             PettyCash.create_entry(manager, %{
               amount: "450",
               category: "Ingredients",
               note: "Ice and drinking water"
             })

    assert entry.note == "Ice and drinking water"

    assert Decimal.equal?(
             PettyCash.total_for_shop_date(Orders.shop_date_today()),
             Decimal.new("450")
           )

    assert {:error, :insufficient_petty_cash} =
             PettyCash.create_entry(manager, %{
               amount: "50.01",
               category: "Other",
               note: "Extra supplies"
             })

    assert {:ok, _last_peso} =
             PettyCash.create_entry(manager, %{
               amount: "50",
               category: "Supplies",
               note: "Cup lids"
             })

    assert Decimal.equal?(
             PettyCash.total_for_shop_date(Orders.shop_date_today()),
             Decimal.new("500")
           )
  end

  test "barista must be on shift, and managers can void with a reason" do
    barista = barista!()
    manager = manager!()

    assert {:error, :not_on_shift} =
             PettyCash.create_entry(barista, %{
               amount: "50",
               category: "Ingredients",
               note: "Ice"
             })

    assert {:ok, _shift} = StaffShifts.open_shift_for_login(barista)

    assert {:ok, entry} =
             PettyCash.create_entry(barista, %{
               amount: "50",
               category: "Ingredients",
               note: "Ice"
             })

    assert {:error, :unauthorized} = PettyCash.void_entry(entry, barista, "Wrong entry")
    assert {:ok, voided} = PettyCash.void_entry(entry, manager, "Entered twice")
    assert voided.status == "voided"

    assert Decimal.equal?(
             PettyCash.total_for_shop_date(Orders.shop_date_today()),
             Decimal.new("0")
           )
  end

  test "closing replenishes the separate float and records a variance with a reason" do
    manager = manager!()

    assert {:ok, _entry} =
             PettyCash.create_entry(manager, %{
               amount: "50",
               category: "Ingredients",
               note: "Ice"
             })

    assert {:error, :petty_cash_notes_required} =
             Shifts.record_close(manager, %{
               counted_cash: "450",
               petty_cash_counted: "440"
             })

    assert {:ok, close} =
             Shifts.record_close(manager, %{
               counted_cash: "440",
               petty_cash_counted: "440",
               petty_cash_notes: "Short by ten pesos"
             })

    assert Decimal.equal?(close.petty_cash_expected, Decimal.new("450"))
    assert Decimal.equal?(close.petty_cash_counted, Decimal.new("440"))
    assert Decimal.equal?(close.petty_cash_variance, Decimal.new("-10"))
    assert Decimal.equal?(close.petty_cash_transfer, Decimal.new("60"))
    assert close.petty_cash_notes == "Short by ten pesos"
    expected_drawer = Shifts.get_open_for_date(Orders.shop_date_today()).opening_cash
    assert Decimal.equal?(close.expected_cash, Decimal.sub(expected_drawer, Decimal.new("60")))
  end

  test "close exports include petty-cash purchases separately from drawer Cash Outs" do
    manager = manager!()
    shop_date = Orders.shop_date_today()

    assert {:ok, _entry} =
             PettyCash.create_entry(manager, %{
               amount: "35",
               category: "Ingredients",
               note: "Ice"
             })

    assert {:ok, pack} = CloseExport.pack(shop_date, shop_date)
    assert [%{note: "Ice", amount: amount}] = pack.petty_cash_entries
    assert Decimal.equal?(amount, Decimal.new("35"))
    assert Enum.at(CloseExport.days_headers(), 9) == "Cash Outs"
    assert "Petty Cash Purchases" in CloseExport.days_headers()

    assert {:ok, {_filename, workbook}} = CloseExport.build_xlsx(pack)
    assert is_binary(workbook)
  end
end
