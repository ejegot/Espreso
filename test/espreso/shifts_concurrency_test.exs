defmodule Espreso.ShiftsConcurrencyTest do
  use Espreso.DataCase, async: false

  alias Espreso.Accounts
  alias Espreso.Shifts
  alias Espreso.StaffShifts

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
        Shifts.record_close(barista, %{notes: "barista"})
      end)

    task_m =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
        Shifts.record_close(manager, %{notes: "manager"})
      end)

    results = [Task.await(task_a, 5_000), Task.await(task_m, 5_000)]

    oks = for {:ok, close} <- results, do: close
    errors = for {:error, reason} <- results, do: reason

    assert length(oks) == 1
    assert :already_closed in errors
    assert %Shifts.ShiftClose{} = Shifts.get_todays_close()
  end
end
