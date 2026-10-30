defmodule Espreso.StaffShiftsConcurrencyTest do
  use Espreso.DataCase, async: false

  import Ecto.Query

  alias Espreso.Accounts
  alias Espreso.Repo
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift

  test "concurrent open_shift_for_login leaves exactly one open shift" do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Conc Shift Staff",
        email: "conc.shift@test.local",
        password: "password123",
        role: "barista"
      })

    parent = self()

    task_a =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
        StaffShifts.open_shift_for_login(user)
      end)

    task_b =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
        StaffShifts.open_shift_for_login(user)
      end)

    results = [Task.await(task_a, 5_000), Task.await(task_b, 5_000)]

    assert Enum.all?(results, &match?({:ok, %StaffShift{}}, &1))

    shift_ids = Enum.map(results, fn {:ok, shift} -> shift.id end)
    assert length(Enum.uniq(shift_ids)) == 1

    open_shifts =
      StaffShift
      |> where([s], s.user_id == ^user.id and is_nil(s.ended_at))
      |> Repo.all()

    assert length(open_shifts) == 1

    all_shifts =
      StaffShift
      |> where([s], s.user_id == ^user.id)
      |> Repo.all()

    assert length(all_shifts) == 1
    assert hd(all_shifts).id == hd(shift_ids)
  end
end
