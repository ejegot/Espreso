defmodule Espreso.StaffShifts do
  @moduledoc """
  Employee attendance shifts (Time In / Time Out).

  Browser login opens a shift; explicit logout closes it.
  Separate from shop-day `Espreso.Shifts` / `ShiftClose`.
  """

  import Ecto.Query

  alias Espreso.Accounts.User
  alias Espreso.Repo
  alias Espreso.StaffShifts.StaffShift

  @doc """
  Returns the employee's currently open staff shift, or `nil`.
  """
  def get_open_shift(%User{id: id}), do: get_open_shift(id)

  def get_open_shift(user_id) when is_integer(user_id) do
    StaffShift
    |> where([s], s.user_id == ^user_id and is_nil(s.ended_at))
    |> Repo.one()
  end

  @doc """
  Opens a staff shift for a successful browser login.

  If an open shift already exists, closes it with `end_reason: "auto_close"`
  and opens a new shift in the same transaction.

  Serializes concurrent logins for the same employee by locking the user row
  (`FOR UPDATE`), then locking any open shift row before close+insert.
  The partial unique index `staff_shifts_one_open_per_user` remains the
  database invariant.
  """
  def open_shift_for_login(%User{} = user) do
    now = utc_now()

    result =
      Repo.transaction(fn ->
        lock_user!(user.id)

        case get_open_shift_for_update(user.id) do
          %StaffShift{} = open ->
            open
            |> StaffShift.close_changeset(%{ended_at: now, end_reason: "auto_close"})
            |> Repo.update()
            |> case do
              {:ok, _} -> :ok
              {:error, changeset} -> Repo.rollback(changeset)
            end

          nil ->
            :ok
        end

        %StaffShift{}
        |> StaffShift.open_changeset(%{user_id: user.id, started_at: now})
        |> Repo.insert()
        |> case do
          {:ok, shift} -> shift
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, %StaffShift{} = shift} -> {:ok, shift}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Closes the employee's open staff shift on explicit logout.

  Returns `{:ok, shift}` when a shift was closed, `{:ok, :none}` when there
  was no open shift.
  """
  def close_shift_for_logout(user_id) when is_integer(user_id) do
    now = utc_now()

    result =
      Repo.transaction(fn ->
        lock_user!(user_id)

        case get_open_shift_for_update(user_id) do
          %StaffShift{} = open ->
            open
            |> StaffShift.close_changeset(%{ended_at: now, end_reason: "logout"})
            |> Repo.update()
            |> case do
              {:ok, shift} -> shift
              {:error, changeset} -> Repo.rollback(changeset)
            end

          nil ->
            :none
        end
      end)

    case result do
      {:ok, %StaffShift{} = shift} -> {:ok, shift}
      {:ok, :none} -> {:ok, :none}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_user!(user_id) do
    User
    |> where([u], u.id == ^user_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp get_open_shift_for_update(user_id) do
    StaffShift
    |> where([s], s.user_id == ^user_id and is_nil(s.ended_at))
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
