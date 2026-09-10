defmodule Espreso.Shifts do
  @moduledoc """
  Light end-of-day shift close snapshots for CoffeeSpot.

  Shop-wide seal (one per Manila shop day). Separate from employee
  `Espreso.StaffShifts` / StaffShift attendance.

  Baristas may seal the day only when they are the last active StaffShift;
  a successful barista close also ends that StaffShift (`end_reason: "shift_close"`).
  Managers/owners retain a management/fallback close path with no StaffShift side effect.
  """

  import Ecto.Query

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.Orders
  alias Espreso.Repo
  alias Espreso.Shifts.ShiftClose
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift

  @doc """
  Returns today's shift close for the current Asia/Manila shop date, if any.
  """
  def get_todays_close do
    get_close_for_date(Orders.shop_date_today())
  end

  def get_close_for_date(%Date{} = shop_date) do
    ShiftClose
    |> where([s], s.shop_date == ^shop_date)
    |> preload(:closed_by_user)
    |> Repo.one()
  end

  @doc """
  True when the user may open the Close Shift screen (barista / manager / owner).
  """
  def can_access_close?(%User{active: true, role: role})
      when role in ~w(barista manager owner),
      do: true

  def can_access_close?(_), do: false

  @doc """
  LiveView eligibility for an open (not yet sealed) shop day.

  - Manager/owner: always `:ok` when the day is open
  - Barista: `:ok` only when they are the sole open StaffShift
  - Otherwise `{:error, :other_staff_active}` or `{:error, :not_on_shift}`
  """
  def close_eligibility(%User{} = user) do
    cond do
      Authorization.can?(user, :reports) ->
        :ok

      barista?(user) ->
        StaffShifts.last_active_closer_status(user)

      true ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Records a shift close for today's shop date.

  Snapshots system paid totals from `Orders.todays_paid_breakdown/0`.
  One close per shop day.

  Baristas must be the last active StaffShift; on success their open StaffShift
  ends with `end_reason: "shift_close"` at the same `closed_at` timestamp.
  Manager/owner closes do not touch StaffShifts.
  """
  def record_close(%User{} = user, attrs \\ %{}) do
    cond do
      Authorization.can?(user, :reports) ->
        do_record_close(user, attrs, :manager)

      barista?(user) ->
        do_record_close(user, attrs, :barista)

      true ->
        {:error, :unauthorized}
    end
  end

  defp do_record_close(%User{} = user, attrs, mode) do
    breakdown = Orders.todays_paid_breakdown()
    shop_date = breakdown.shop_date
    closed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    counted_cash =
      parse_optional_decimal(Map.get(attrs, :counted_cash) || Map.get(attrs, "counted_cash"))

    notes = normalize_notes(Map.get(attrs, :notes) || Map.get(attrs, "notes"))

    result =
      Repo.transaction(fn ->
        lock_shop_close!(shop_date)

        case get_close_for_date(shop_date) do
          %ShiftClose{} ->
            Repo.rollback(:already_closed)

          nil ->
            :ok
        end

        if mode == :barista do
          StaffShifts.assert_last_active_closer!(user)
        end

        close =
          %ShiftClose{}
          |> ShiftClose.changeset(%{
            shop_date: shop_date,
            system_total: breakdown.total,
            system_count: breakdown.count,
            by_via: serialize_by_via(breakdown.by_via),
            counted_cash: counted_cash,
            notes: notes,
            closed_by_user_id: user.id,
            closed_at: closed_at
          })
          |> Repo.insert()
          |> case do
            {:ok, close} ->
              close

            {:error, %Ecto.Changeset{errors: errors} = changeset} ->
              if Keyword.has_key?(errors, :shop_date) do
                Repo.rollback(:already_closed)
              else
                Repo.rollback(changeset)
              end
          end

        if mode == :barista do
          case StaffShifts.do_close_open_shift!(user.id, closed_at, "shift_close") do
            %StaffShift{} ->
              :ok

            :none ->
              Repo.rollback(:not_on_shift)
          end
        end

        Repo.preload(close, :closed_by_user)
      end)

    case result do
      {:ok, %ShiftClose{} = close} -> {:ok, close}
      {:error, :already_closed} -> {:error, :already_closed}
      {:error, :other_staff_active} -> {:error, :other_staff_active}
      {:error, :not_on_shift} -> {:error, :not_on_shift}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_shop_close!(%Date{} = shop_date) do
    key = :erlang.phash2({:espreso_shop_close, Date.to_iso8601(shop_date)})
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [key])
    :ok
  end

  defp barista?(%User{role: "barista", active: true}), do: true
  defp barista?(_), do: false

  @doc """
  Formats a close timestamp in Asia/Manila for staff UI.
  """
  def format_closed_at(%DateTime{} = closed_at) do
    manila =
      closed_at
      |> DateTime.add(8 * 60 * 60, :second)

    Calendar.strftime(manila, "%I:%M %p")
    |> String.trim_leading("0")
  end

  def format_closed_at(_), do: ""

  defp serialize_by_via(by_via) when is_map(by_via) do
    Map.new(by_via, fn {via, %{total: total, count: count}} ->
      {via, %{"total" => Decimal.to_string(total), "count" => count}}
    end)
  end

  defp parse_optional_decimal(nil), do: nil
  defp parse_optional_decimal(""), do: nil
  defp parse_optional_decimal(%Decimal{} = value), do: value

  defp parse_optional_decimal(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp parse_optional_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp parse_optional_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp parse_optional_decimal(_), do: nil

  defp normalize_notes(nil), do: nil

  defp normalize_notes(notes) when is_binary(notes) do
    case String.trim(notes) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_notes(_), do: nil
end
