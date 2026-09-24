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
  alias Espreso.CashOuts
  alias Espreso.Orders
  alias Espreso.Repo
  alias Espreso.Shifts.ShopDayOpen
  alias Espreso.Shifts.ShiftClose
  alias Espreso.StaffShifts
  alias Espreso.StaffShifts.StaffShift

  @close_history_page_size 25

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
  Sealed close snapshots whose `shop_date` falls in the inclusive range.
  """
  def list_closes_for_shop_dates(%Date{} = from_date, %Date{} = to_date) do
    ShiftClose
    |> where([s], s.shop_date >= ^from_date and s.shop_date <= ^to_date)
    |> order_by([s], asc: s.shop_date)
    |> preload(:closed_by_user)
    |> Repo.all()
  end

  @doc """
  Opening-cash rows whose `shop_date` falls in the inclusive range.
  """
  def list_opens_for_shop_dates(%Date{} = from_date, %Date{} = to_date) do
    ShopDayOpen
    |> where([o], o.shop_date >= ^from_date and o.shop_date <= ^to_date)
    |> order_by([o], asc: o.shop_date)
    |> preload(:opened_by_user)
    |> Repo.all()
  end

  @doc """
  Read-only Close Shift history, newest Manila `shop_date` first.

  Because `shop_date` is unique, keyset pagination uses that date alone:
  optional `:cursor` is a `%Date{}` and fetches rows with `shop_date < cursor`.

  Optional `opts`:
  - `:limit` — page size (default #{@close_history_page_size}, clamped 1..100)
  - `:cursor` — last visible `shop_date` from the previous page

  Returns `%{closes, has_next_page, next_cursor}`.
  Does not recompute totals from orders — returns sealed snapshot rows as stored.
  """
  def list_close_history(opts \\ []) when is_list(opts) do
    limit =
      opts
      |> Keyword.get(
        :limit,
        Application.get_env(:espreso, :close_history_page_size, @close_history_page_size)
      )
      |> close_history_page_limit()

    cursor = normalize_close_history_cursor(Keyword.get(opts, :cursor))

    query =
      ShiftClose
      |> apply_close_history_cursor(cursor)
      |> order_by([s], desc: s.shop_date)
      |> limit(^(limit + 1))
      |> preload(:closed_by_user)

    rows = Repo.all(query)
    has_next_page? = length(rows) > limit
    closes = Enum.take(rows, limit)

    next_cursor =
      if has_next_page? do
        case List.last(closes) do
          %ShiftClose{shop_date: %Date{} = shop_date} -> shop_date
          _ -> nil
        end
      else
        nil
      end

    %{
      closes: closes,
      has_next_page: has_next_page?,
      next_cursor: next_cursor
    }
  end

  defp close_history_page_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, 100)
  defp close_history_page_limit(_), do: @close_history_page_size

  defp normalize_close_history_cursor(%Date{} = shop_date), do: shop_date

  defp normalize_close_history_cursor(shop_date) when is_binary(shop_date) do
    case Date.from_iso8601(shop_date) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp normalize_close_history_cursor(_), do: nil

  defp apply_close_history_cursor(query, nil), do: query

  defp apply_close_history_cursor(query, %Date{} = shop_date) do
    from(s in query, where: s.shop_date < ^shop_date)
  end

  @doc """
  True when the user may open the Close Shift screen (barista / manager / owner).
  """
  def can_access_close?(%User{active: true, role: role})
      when role in ~w(barista manager owner),
      do: true

  def can_access_close?(_), do: false

  def can_access_open?(user), do: can_access_close?(user)

  @doc """
  Manila shop-day sales gate: `:open`, `:not_open`, or `:closed`.
  """
  def shop_day_status do
    shop_date = Orders.shop_date_today()

    cond do
      not is_nil(get_close_for_date(shop_date)) -> :closed
      is_nil(get_open_for_date(shop_date)) -> :not_open
      true -> :open
    end
  end

  @doc """
  New sales and cash drawer movements are allowed only while the shop day
  is opened and not yet sealed.
  """
  def assert_selling_allowed do
    case shop_day_status() do
      :open -> :ok
      :not_open -> {:error, :shop_not_open}
      :closed -> {:error, :shop_day_closed}
    end
  end

  def selling_blocked_message(:shop_not_open),
    do: "Record opening cash before selling. Open shop once at the start of the day."

  def selling_blocked_message(:shop_day_closed),
    do: "Shop day is closed. No new sales until tomorrow."

  def selling_blocked_message(_), do: "Selling is not available right now."

  @doc """
  Today's shop-day opening cash, if recorded.
  """
  def get_todays_open do
    get_open_for_date(Orders.shop_date_today())
  end

  def get_open_for_date(%Date{} = shop_date) do
    ShopDayOpen
    |> where([o], o.shop_date == ^shop_date)
    |> preload(:opened_by_user)
    |> Repo.one()
  end

  @doc """
  Records opening drawer cash for today's shop date.

  One open per shop day. Blocked after the day is already sealed.
  Barista, manager, and owner may record it (attendance Time In is separate).
  """
  def record_open(%User{} = user, attrs \\ %{}) do
    if can_access_open?(user) do
      do_record_open(user, attrs)
    else
      {:error, :unauthorized}
    end
  end

  defp do_record_open(%User{} = user, attrs) do
    shop_date = Orders.shop_date_today()
    opened_at = DateTime.utc_now() |> DateTime.truncate(:second)

    opening_cash =
      parse_required_decimal(Map.get(attrs, :opening_cash) || Map.get(attrs, "opening_cash"))

    notes = normalize_notes(Map.get(attrs, :notes) || Map.get(attrs, "notes"))

    if is_nil(opening_cash) do
      {:error, :opening_cash_required}
    else
      result =
        Repo.transaction(fn ->
          lock_shop_open!(shop_date)

          if get_close_for_date(shop_date) do
            Repo.rollback(:already_closed)
          end

          if get_open_for_date(shop_date) do
            Repo.rollback(:already_open)
          end

          %ShopDayOpen{}
          |> ShopDayOpen.changeset(%{
            shop_date: shop_date,
            opening_cash: opening_cash,
            opened_at: opened_at,
            opened_by_user_id: user.id,
            notes: notes
          })
          |> Repo.insert()
          |> case do
            {:ok, open} ->
              Repo.preload(open, :opened_by_user)

            {:error, %Ecto.Changeset{errors: errors} = changeset} ->
              if Keyword.has_key?(errors, :shop_date) do
                Repo.rollback(:already_open)
              else
                Repo.rollback(changeset)
              end
          end
        end)

      case result do
        {:ok, %ShopDayOpen{} = open} -> {:ok, open}
        {:error, :already_open} -> {:error, :already_open}
        {:error, :already_closed} -> {:error, :already_closed}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Expected drawer cash: opening + cash sales − cash outs.

  Missing opening cash is treated as ₱0 so close still works, with a visible gap.
  """
  def expected_drawer_cash(opening_cash, cash_sales, cash_out_total) do
    Decimal.sub(
      Decimal.add(decimalize_money(opening_cash), decimalize_money(cash_sales)),
      decimalize_money(cash_out_total)
    )
    |> Decimal.round(2)
  end

  def drawer_variance(counted_cash, expected_cash) do
    Decimal.sub(decimalize_money(counted_cash), decimalize_money(expected_cash))
    |> Decimal.round(2)
  end

  def cash_sales_total(%{by_via: by_via}) when is_map(by_via) do
    entry = Map.get(by_via, "cash") || Map.get(by_via, :cash) || %{}
    total = Map.get(entry, :total) || Map.get(entry, "total") || Decimal.new("0")
    decimalize_money(total)
  end

  def cash_sales_total(_), do: Decimal.new("0")

  @doc """
  Cash taken out of the drawer implied by a sealed close snapshot.

  `opening + cash sales - expected`. Zero when opening or expected is missing.
  """
  def implied_cash_outs(%{opening_cash: opening, expected_cash: expected} = close)
      when not is_nil(opening) and not is_nil(expected) do
    cash_sales_total(close)
    |> Decimal.add(decimalize_money(opening))
    |> Decimal.sub(decimalize_money(expected))
    |> Decimal.round(2)
  end

  def implied_cash_outs(_), do: Decimal.new("0")

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
      parse_required_decimal(Map.get(attrs, :counted_cash) || Map.get(attrs, "counted_cash"))

    notes = normalize_notes(Map.get(attrs, :notes) || Map.get(attrs, "notes"))

    if is_nil(counted_cash) do
      {:error, :counted_cash_required}
    else
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

          opening = get_open_for_date(shop_date)
          opening_cash = opening && opening.opening_cash
          cash_sales = cash_sales_total(breakdown)
          cash_out_total = CashOuts.total_for_shop_date(shop_date)
          expected_cash = expected_drawer_cash(opening_cash, cash_sales, cash_out_total)
          variance = drawer_variance(counted_cash, expected_cash)

          close =
            %ShiftClose{}
            |> ShiftClose.changeset(%{
              shop_date: shop_date,
              system_total: breakdown.total,
              system_count: breakdown.count,
              by_via: serialize_by_via(breakdown.by_via),
              counted_cash: counted_cash,
              opening_cash: opening_cash,
              expected_cash: expected_cash,
              variance: variance,
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
  end

  defp lock_shop_open!(%Date{} = shop_date) do
    key = :erlang.phash2({:espreso_shop_open, Date.to_iso8601(shop_date)})
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [key])
    :ok
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

  defp parse_required_decimal(value) do
    case parse_optional_decimal(value) do
      %Decimal{} = decimal ->
        if Decimal.compare(decimal, 0) == :lt, do: nil, else: Decimal.round(decimal, 2)

      _ ->
        nil
    end
  end

  defp decimalize_money(nil), do: Decimal.new("0")
  defp decimalize_money(%Decimal{} = value), do: Decimal.round(value, 2)

  defp decimalize_money(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} -> Decimal.round(decimal, 2)
      _ -> Decimal.new("0")
    end
  end

  defp decimalize_money(value) when is_integer(value), do: Decimal.new(value)
  defp decimalize_money(_), do: Decimal.new("0")

  defp normalize_notes(nil), do: nil

  defp normalize_notes(notes) when is_binary(notes) do
    case String.trim(notes) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_notes(_), do: nil
end
