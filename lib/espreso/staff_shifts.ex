defmodule Espreso.StaffShifts do
  @moduledoc """
  Employee attendance shifts (Time In / Time Out).

  Browser login opens a shift; explicit logout closes it.
  A successful shop-day Close Shift may also end the closing barista's shift
  with `end_reason: "shift_close"`.

  Separate from shop-day `Espreso.Shifts` / `ShiftClose`.
  """

  import Ecto.Query

  alias Espreso.Accounts.User
  alias Espreso.Orders
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
  All currently open staff shifts (`ended_at` is nil), ordered by id.

  Used for last-active Close Shift eligibility. Optional `:lock` loads rows
  with `FOR UPDATE` (call inside a transaction).
  """
  def list_open_shifts(opts \\ []) when is_list(opts) do
    query =
      StaffShift
      |> where([s], is_nil(s.ended_at))
      |> order_by([s], asc: s.id)
      |> preload(:user)

    query =
      if Keyword.get(opts, :lock, false) do
        lock(query, "FOR UPDATE")
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Whether a barista is the sole open StaffShift (last active staff).

  Returns `:ok`, `{:error, :not_on_shift}`, or `{:error, :other_staff_active}`.
  """
  def last_active_closer_status(%User{role: "barista", active: true} = user) do
    opens = list_open_shifts()
    classify_last_active(user.id, opens)
  end

  def last_active_closer_status(_), do: {:error, :not_on_shift}

  @doc false
  def assert_last_active_closer!(%User{role: "barista", active: true} = user) do
    opens = list_open_shifts(lock: true)

    case classify_last_active(user.id, opens) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def assert_last_active_closer!(_user), do: Repo.rollback(:not_on_shift)

  @doc """
  Lists attendance shifts for one employee, newest first.

  Includes open and closed shifts. Options:
  - `:limit` — max rows (default 30, clamped 1..100)
  """
  def list_shifts_for_user(user_id, opts \\ []) when is_integer(user_id) and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 30) |> normalize_limit()

    StaffShift
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], desc: s.started_at, desc: s.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @shift_history_page_size 30

  @doc """
  Closed attendance-shift history for one employee, newest first.

  Excludes the currently open shift (`ended_at` is not nil). Ordering is
  `started_at DESC, id DESC`. Optional `:cursor` is
  `%{started_at: DateTime.t(), id: integer()}` from the previous page's last
  row and fetches strictly older rows.

  Optional `opts`:
  - `:limit` — page size (default #{@shift_history_page_size}, clamped 1..100)
  - `:cursor` — keyset cursor from the previous page

  Returns `%{shifts, has_next_page, next_cursor}`.
  """
  def list_shift_history_for_user(user_id, opts \\ [])
      when is_integer(user_id) and is_list(opts) do
    limit =
      opts
      |> Keyword.get(
        :limit,
        Application.get_env(:espreso, :staff_shift_history_page_size, @shift_history_page_size)
      )
      |> normalize_limit()

    cursor = normalize_shift_history_cursor(Keyword.get(opts, :cursor))

    query =
      StaffShift
      |> where([s], s.user_id == ^user_id and not is_nil(s.ended_at))
      |> apply_shift_history_cursor(cursor)
      |> order_by([s], desc: s.started_at, desc: s.id)
      |> limit(^(limit + 1))

    rows = Repo.all(query)
    has_next_page? = length(rows) > limit
    shifts = Enum.take(rows, limit)

    next_cursor =
      if has_next_page? do
        case List.last(shifts) do
          %StaffShift{started_at: %DateTime{} = started_at, id: id} when is_integer(id) ->
            %{started_at: started_at, id: id}

          _ ->
            nil
        end
      else
        nil
      end

    %{
      shifts: shifts,
      has_next_page: has_next_page?,
      next_cursor: next_cursor
    }
  end

  defp normalize_shift_history_cursor(%{started_at: %DateTime{} = started_at, id: id})
       when is_integer(id) and id > 0 do
    %{started_at: DateTime.truncate(started_at, :second), id: id}
  end

  defp normalize_shift_history_cursor(%{"started_at" => started_at, "id" => id}) do
    normalize_shift_history_cursor(%{started_at: started_at, id: id})
  end

  defp normalize_shift_history_cursor(_), do: nil

  defp apply_shift_history_cursor(query, nil), do: query

  defp apply_shift_history_cursor(query, %{started_at: started_at, id: id}) do
    from(s in query,
      where:
        s.started_at < ^started_at or
          (s.started_at == ^started_at and s.id < ^id)
    )
  end

  @doc """
  Lists all employee staff shifts that overlap an Asia/Manila shop day.

  Uses `Orders.shop_day_bounds_utc/1`. Open shifts first, then newest
  `started_at`. Preloads `:user`.
  """
  def list_shifts_for_shop_day(%Date{} = shop_date) do
    {day_start, day_end} = Orders.shop_day_bounds_utc(shop_date)

    StaffShift
    |> where(
      [s],
      s.started_at < ^day_end and (is_nil(s.ended_at) or s.ended_at > ^day_start)
    )
    |> order_by([s],
      asc: fragment("CASE WHEN ? IS NULL THEN 0 ELSE 1 END", s.ended_at),
      desc: s.started_at,
      desc: s.id
    )
    |> preload(:user)
    |> Repo.all()
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
    close_open_shift(user_id, utc_now(), "logout")
  end

  @doc """
  Ends the employee's open staff shift after a successful shop-day ShiftClose.

  `ended_at` should be the ShiftClose `closed_at` timestamp.
  Returns `{:ok, shift}`, `{:ok, :none}` when there was no open shift, or
  `{:error, reason}`.
  """
  def close_shift_for_shift_close(user_id, %DateTime{} = ended_at) when is_integer(user_id) do
    close_open_shift(user_id, DateTime.truncate(ended_at, :second), "shift_close")
  end

  defp close_open_shift(user_id, ended_at, end_reason) do
    result =
      Repo.transaction(fn ->
        do_close_open_shift!(user_id, ended_at, end_reason)
      end)

    case result do
      {:ok, %StaffShift{} = shift} -> {:ok, shift}
      {:ok, :none} -> {:ok, :none}
      {:error, reason} -> {:error, reason}
    end
  end

  # Must run inside an open Repo transaction (nested savepoint is fine).
  @doc false
  def do_close_open_shift!(user_id, %DateTime{} = ended_at, end_reason)
      when is_integer(user_id) and is_binary(end_reason) do
    lock_user!(user_id)

    case get_open_shift_for_update(user_id) do
      %StaffShift{} = open ->
        open
        |> StaffShift.close_changeset(%{ended_at: ended_at, end_reason: end_reason})
        |> Repo.update()
        |> case do
          {:ok, shift} -> shift
          {:error, changeset} -> Repo.rollback(changeset)
        end

      nil ->
        :none
    end
  end

  defp classify_last_active(user_id, opens) do
    own? = Enum.any?(opens, &(&1.user_id == user_id))
    others? = Enum.any?(opens, &(&1.user_id != user_id))

    cond do
      not own? -> {:error, :not_on_shift}
      others? -> {:error, :other_staff_active}
      true -> :ok
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

  defp normalize_limit(limit) when is_integer(limit) and limit > 0 do
    min(limit, 100)
  end

  defp normalize_limit(_), do: 30
end
