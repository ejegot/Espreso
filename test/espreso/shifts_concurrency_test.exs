defmodule Espreso.ShiftsConcurrencyTest do
  use Espreso.DataCase, async: false

  alias Espreso.Accounts
  alias Espreso.Shifts
  alias Espreso.StaffShifts

  @tag :without_shop_open
  test "concurrent opening attempts leave one active session" do
    {:ok, manager} =
      Accounts.register_user(%{
        name: "Opening Manager",
        email: "conc.open.manager@test.local",
        password: "password123",
        role: "manager"
      })

    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
          Shifts.record_open(manager, %{opening_cash: "10"})
        end)
      end

    results = Enum.map(tasks, &Task.await(&1, 5_000))
    assert Enum.count(results, &match?({:ok, %Shifts.ShopDayOpen{}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :already_open}, &1)) == 1
    assert %Shifts.ShopDayOpen{session_active: true} = Shifts.current_session()
  end

  test "concurrent close attempts yield exactly one ShiftClose" do
    {:ok, barista} =
      Accounts.register_user(%{
        name: "Conc Close Barista",
        email: "conc.close.barista@test.local",
        password: "password123",
        role: "barista"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Conc Close Manager",
        email: "conc.close.manager@test.local",
        password: "password123",
        role: "manager"
      })

    assert {:ok, _} = StaffShifts.open_shift_for_login(barista)

    parent = self()

    task_a =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
        Shifts.record_close(barista, %{counted_cash: "10", notes: "barista"})
      end)

    task_m =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
        Shifts.record_close(manager, %{counted_cash: "10", notes: "manager"})
      end)

    results = [Task.await(task_a, 5_000), Task.await(task_m, 5_000)]

    oks = for {:ok, close} <- results, do: close
    errors = for {:error, reason} <- results, do: reason

    assert length(oks) == 1
    assert :already_closed in errors
    assert %Shifts.ShiftClose{} = Shifts.get_todays_close()
  end
end
