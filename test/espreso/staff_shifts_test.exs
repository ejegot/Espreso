defmodule Espreso.StaffShiftsTest do
  use Espreso.DataCase, async: true

  import Ecto.Query

  alias Espreso.Accounts
  alias Espreso.Orders
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

  describe "close_shift_for_shift_close/2" do
    test "closes open shift with shift_close reason and given ended_at", %{user: user} do
      assert {:ok, open} = StaffShifts.open_shift_for_login(user)
      ended_at = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, closed} = StaffShifts.close_shift_for_shift_close(user.id, ended_at)

      assert closed.id == open.id
      assert closed.end_reason == "shift_close"
      assert DateTime.compare(closed.ended_at, ended_at) == :eq
      assert is_nil(StaffShifts.get_open_shift(user))
    end

    test "does not close another user's open shift", %{user: user} do
      {:ok, other} =
        Accounts.register_user(%{
          name: "Other Closer",
          email: "other.closer@test.local",
          password: "password123",
          role: "barista"
        })

      assert {:ok, open_user} = StaffShifts.open_shift_for_login(user)
      assert {:ok, open_other} = StaffShifts.open_shift_for_login(other)

      ended_at = DateTime.utc_now() |> DateTime.truncate(:second)
      assert {:ok, closed} = StaffShifts.close_shift_for_shift_close(user.id, ended_at)

      assert closed.id == open_user.id
      assert StaffShifts.get_open_shift(other).id == open_other.id
      assert is_nil(Repo.get!(StaffShift, open_other.id).ended_at)
    end

    test "no open shift is a successful no-op", %{user: user} do
      ended_at = DateTime.utc_now() |> DateTime.truncate(:second)
      assert {:ok, :none} = StaffShifts.close_shift_for_shift_close(user.id, ended_at)
    end
  end

  describe "last_active_closer_status/1" do
    test "ok only when barista is sole open shift", %{user: user} do
      assert {:error, :not_on_shift} = StaffShifts.last_active_closer_status(user)

      assert {:ok, _} = StaffShifts.open_shift_for_login(user)
      assert :ok = StaffShifts.last_active_closer_status(user)

      {:ok, other} =
        Accounts.register_user(%{
          name: "Peer",
          email: "peer.last.active@test.local",
          password: "password123",
          role: "barista"
        })

      assert {:ok, _} = StaffShifts.open_shift_for_login(other)
      assert {:error, :other_staff_active} = StaffShifts.last_active_closer_status(user)
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

  describe "list_shifts_for_user/2" do
    test "returns only the requested user's shifts, newest first", %{user: user} do
      {:ok, other} =
        Accounts.register_user(%{
          name: "Other Staff",
          email: "other.list.shifts@test.local",
          password: "password123",
          role: "barista"
        })

      older =
        insert_shift!(user, ~U[2026-09-09 01:00:00Z], ~U[2026-09-09 09:00:00Z])

      newer_closed =
        insert_shift!(user, ~U[2026-09-10 01:00:00Z], ~U[2026-09-10 05:00:00Z])

      {:ok, open} = StaffShifts.open_shift_for_login(user)
      {:ok, _other_open} = StaffShifts.open_shift_for_login(other)

      shifts = StaffShifts.list_shifts_for_user(user.id)

      assert Enum.map(shifts, & &1.id) == [open.id, newer_closed.id, older.id]
      assert Enum.all?(shifts, &(&1.user_id == user.id))
      assert Enum.any?(shifts, &is_nil(&1.ended_at))
      assert Enum.count(shifts, &(&1.ended_at != nil)) == 2
    end

    test "respects limit option", %{user: user} do
      for hour <- 1..5 do
        start = DateTime.new!(~D[2026-09-08], Time.new!(hour, 0, 0), "Etc/UTC")
        ended = DateTime.add(start, 3600, :second)

        insert_shift!(user, start, ended)
      end

      assert length(StaffShifts.list_shifts_for_user(user.id, limit: 2)) == 2
      assert length(StaffShifts.list_shifts_for_user(user.id, limit: 100)) == 5
    end

    test "isolates multiple users", %{user: user} do
      {:ok, other} =
        Accounts.register_user(%{
          name: "Isolated Staff",
          email: "isolated.list.shifts@test.local",
          password: "password123",
          role: "barista"
        })

      insert_shift!(user, ~U[2026-09-10 01:00:00Z], ~U[2026-09-10 02:00:00Z])
      insert_shift!(other, ~U[2026-09-10 03:00:00Z], ~U[2026-09-10 04:00:00Z])

      user_shifts = StaffShifts.list_shifts_for_user(user.id)
      other_shifts = StaffShifts.list_shifts_for_user(other.id)

      assert length(user_shifts) == 1
      assert length(other_shifts) == 1
      assert hd(user_shifts).user_id == user.id
      assert hd(other_shifts).user_id == other.id
    end
  end

  describe "list_shifts_for_shop_day/1" do
    setup do
      shop_date = ~D[2026-09-10]
      {day_start, day_end} = Orders.shop_day_bounds_utc(shop_date)

      employees =
        for {name, email} <- [
              {"Ana Attendance", "ana.attendance@test.local"},
              {"Ben Attendance", "ben.attendance@test.local"},
              {"Cara Attendance", "cara.attendance@test.local"},
              {"Dan Attendance", "dan.attendance@test.local"},
              {"Eve Attendance", "eve.attendance@test.local"},
              {"Fay Attendance", "fay.attendance@test.local"}
            ] do
          {:ok, user} =
            Accounts.register_user(%{
              name: name,
              email: email,
              password: "password123",
              role: "barista"
            })

          user
        end

      [ana, ben, cara, dan, eve, fay] = employees

      %{
        shop_date: shop_date,
        day_start: day_start,
        day_end: day_end,
        ana: ana,
        ben: ben,
        cara: cara,
        dan: dan,
        eve: eve,
        fay: fay
      }
    end

    test "includes overlapping shifts and excludes shifts outside the shop day", %{
      shop_date: shop_date,
      day_start: day_start,
      day_end: day_end,
      ana: ana,
      ben: ben,
      cara: cara,
      dan: dan,
      eve: eve,
      fay: fay
    } do
      open_today = insert_open_shift!(ana, DateTime.add(day_start, 2 * 3600, :second))

      closed_today =
        insert_shift!(
          ben,
          DateTime.add(day_start, 3 * 3600, :second),
          DateTime.add(day_start, 8 * 3600, :second)
        )

      overnight_open = insert_open_shift!(cara, DateTime.add(day_start, -3 * 3600, :second))

      overlap_start =
        insert_shift!(
          dan,
          DateTime.add(day_start, -3600, :second),
          DateTime.add(day_start, 1800, :second)
        )

      overlap_end =
        insert_shift!(
          eve,
          DateTime.add(day_end, -1800, :second),
          DateTime.add(day_end, 3600, :second)
        )

      before_day =
        insert_shift!(
          fay,
          DateTime.add(day_start, -5 * 3600, :second),
          DateTime.add(day_start, -60, :second)
        )

      after_day =
        insert_shift!(
          fay,
          day_end,
          DateTime.add(day_end, 2 * 3600, :second)
        )

      shifts = StaffShifts.list_shifts_for_shop_day(shop_date)
      ids = Enum.map(shifts, & &1.id)

      assert open_today.id in ids
      assert closed_today.id in ids
      assert overnight_open.id in ids
      assert overlap_start.id in ids
      assert overlap_end.id in ids
      refute before_day.id in ids
      refute after_day.id in ids

      assert Enum.all?(shifts, &Ecto.assoc_loaded?(&1.user))
      assert Enum.map(shifts, & &1.user.name) |> Enum.any?(&(&1 == "Ana Attendance"))

      {opens, closeds} = Enum.split_with(shifts, &is_nil(&1.ended_at))
      assert length(opens) == 2

      assert Enum.map(opens, & &1.id) ==
               opens
               |> Enum.sort_by(&{&1.started_at, &1.id}, :desc)
               |> Enum.map(& &1.id)

      assert hd(shifts).id in Enum.map(opens, & &1.id)

      closed_ids = Enum.map(closeds, & &1.id)

      assert closed_ids ==
               closeds
               |> Enum.sort_by(&{&1.started_at, &1.id}, :desc)
               |> Enum.map(& &1.id)
    end

    test "orders open shifts before closed shifts", %{
      shop_date: shop_date,
      day_start: day_start,
      ana: ana,
      ben: ben
    } do
      closed =
        insert_shift!(
          ben,
          DateTime.add(day_start, 5 * 3600, :second),
          DateTime.add(day_start, 6 * 3600, :second)
        )

      open = insert_open_shift!(ana, DateTime.add(day_start, 1 * 3600, :second))

      [first | rest] = StaffShifts.list_shifts_for_shop_day(shop_date)
      assert first.id == open.id
      assert Enum.any?(rest, &(&1.id == closed.id))
    end
  end

  defp insert_open_shift!(user, started_at) do
    {:ok, shift} =
      %StaffShift{}
      |> StaffShift.open_changeset(%{user_id: user.id, started_at: started_at})
      |> Repo.insert()

    shift
  end

  defp insert_shift!(user, started_at, ended_at, end_reason \\ "logout") do
    {:ok, shift} =
      %StaffShift{}
      |> StaffShift.open_changeset(%{user_id: user.id, started_at: started_at})
      |> Repo.insert()

    shift
    |> StaffShift.close_changeset(%{ended_at: ended_at, end_reason: end_reason})
    |> Repo.update!()
  end
end
