defmodule Espreso.StaffShiftsTest do
  use Espreso.DataCase, async: true

  import Ecto.Query

  alias Espreso.Accounts
  alias Espreso.Repo
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Shift Staff",
        email: "shift.staff@test.local",
        password: "password123",
        role: "barista"
      })

    %{user: user}
  end

  describe "open_shift_for_login/1" do
    test "creates an open shift with expected fields", %{user: user} do
      assert {:ok, shift} = StaffShifts.open_shift_for_login(user)

      assert shift.user_id == user.id
      assert %DateTime{} = shift.started_at
      assert shift.started_at.time_zone == "Etc/UTC"
      assert is_nil(shift.ended_at)
      assert is_nil(shift.end_reason)
      assert StaffShifts.get_open_shift(user) == shift
    end

    test "auto-closes existing open shift and opens a new one", %{user: user} do
      assert {:ok, first} = StaffShifts.open_shift_for_login(user)
      assert {:ok, second} = StaffShifts.open_shift_for_login(user)

      first = Repo.get!(StaffShift, first.id)
      assert first.end_reason == "auto_close"
      assert %DateTime{} = first.ended_at
      assert is_nil(second.ended_at)
      assert is_nil(second.end_reason)
      assert DateTime.compare(second.started_at, first.started_at) in [:gt, :eq]
      assert DateTime.compare(second.started_at, first.ended_at) in [:gt, :eq]
      assert StaffShifts.get_open_shift(user).id == second.id

      open_count =
        StaffShift
        |> where([s], s.user_id == ^user.id and is_nil(s.ended_at))
        |> Repo.aggregate(:count, :id)

      assert open_count == 1

      total =
        StaffShift
        |> where([s], s.user_id == ^user.id)
        |> Repo.aggregate(:count, :id)

      assert total == 2
    end
  end

  describe "close_shift_for_logout/1" do
    test "closes open shift with logout reason", %{user: user} do
      assert {:ok, open} = StaffShifts.open_shift_for_login(user)
      assert {:ok, closed} = StaffShifts.close_shift_for_logout(user.id)

      assert closed.id == open.id
      assert closed.end_reason == "logout"
      assert %DateTime{} = closed.ended_at
      assert is_nil(StaffShifts.get_open_shift(user))
    end

    test "logout with no open shift is a successful no-op", %{user: user} do
      assert {:ok, :none} = StaffShifts.close_shift_for_logout(user.id)
      assert is_nil(StaffShifts.get_open_shift(user))
    end
  end

  describe "StaffShift changesets" do
    test "rejects invalid end_reason" do
      {:ok, user} =
        Accounts.register_user(%{
          name: "Invalid Reason",
          email: "invalid.reason@test.local",
          password: "password123",
          role: "barista"
        })

      assert {:ok, open} = StaffShifts.open_shift_for_login(user)

      changeset =
        StaffShift.close_changeset(open, %{
          ended_at: DateTime.utc_now() |> DateTime.truncate(:second),
          end_reason: "manual"
        })

      refute changeset.valid?
      assert %{end_reason: _} = errors_on(changeset)
    end

    test "close requires ended_at and end_reason together" do
      {:ok, user} =
        Accounts.register_user(%{
          name: "Incomplete Close",
          email: "incomplete.close@test.local",
          password: "password123",
          role: "barista"
        })

      assert {:ok, open} = StaffShifts.open_shift_for_login(user)

      changeset = StaffShift.close_changeset(open, %{end_reason: "logout"})
      refute changeset.valid?
      assert %{ended_at: _} = errors_on(changeset)
    end
  end

  describe "database invariant" do
    test "cannot leave two open shifts for the same employee", %{user: user} do
      assert {:ok, _} = StaffShifts.open_shift_for_login(user)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:error, changeset} =
               %StaffShift{}
               |> StaffShift.open_changeset(%{user_id: user.id, started_at: now})
               |> Repo.insert()

      assert %{user_id: _} = errors_on(changeset)

      open_count =
        StaffShift
        |> where([s], s.user_id == ^user.id and is_nil(s.ended_at))
        |> Repo.aggregate(:count, :id)

      assert open_count == 1
    end
  end
end
