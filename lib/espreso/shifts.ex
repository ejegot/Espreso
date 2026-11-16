defmodule Espreso.Shifts do
  @moduledoc """
  Shop sessions and close snapshots for CoffeeSpot.

  Shop-wide sessions are separate from employee
  `Espreso.StaffShifts` / StaffShift attendance.

  Baristas may seal the day only when they are the last active StaffShift.
  Closing the shop does not end an employee's attendance shift.
  """

  import Ecto.Query

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.CashOuts
  alias Espreso.Orders
  alias Espreso.PettyCash
  alias Espreso.Repo
  alias Espreso.Shifts.ShopDayOpen
  alias Espreso.Shifts.ShiftClose
  alias Espreso.StaffShifts
  alias Espreso.Tenancy

  @close_history_page_size 25

  @doc """
  Returns today's shift close for the current Asia/Manila shop date, if any.
  """
  def get_todays_close do
    if current_session() do
      nil
    else
      ShiftClose
      |> Tenancy.scope_to_branch()
      |> where([s], not is_nil(s.shop_session_id) or s.shop_date == ^Orders.shop_date_today())
      |> order_by([s], desc: s.closed_at, desc: s.id)
      |> limit(1)
      |> preload(:closed_by_user)
      |> Repo.one()
    end
  end

  def get_close_for_date(%Date{} = shop_date) do
    ShiftClose
    |> Tenancy.scope_to_branch()
    |> where([s], s.shop_date == ^shop_date)
    |> order_by([s], desc: s.closed_at, desc: s.id)
    |> limit(1)
    |> preload(:closed_by_user)
    |> Repo.one()
  end

  @doc """
  Sealed close snapshots whose `shop_date` falls in the inclusive range.
  """
  def list_closes_for_shop_dates(%Date{} = from_date, %Date{} = to_date) do
    ShiftClose
    |> Tenancy.scope_to_branch()
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
    |> Tenancy.scope_to_branch()
    |> where([o], o.shop_date >= ^from_date and o.shop_date <= ^to_date)
    |> order_by([o], asc: o.shop_date)
    |> preload(:opened_by_user)
    |> Repo.all()
  end

  @doc """
  Read-only Close Shift history, newest Manila `shop_date` first.

  Keyset pagination uses the business date and close ID so multiple sessions
  opened on the same date remain visible.

  Optional `opts`:
  - `:limit` — page size (default #{@close_history_page_size}, clamped 1..100)
  - `:cursor` — `next_cursor` from the previous page

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
      |> Tenancy.scope_to_branch()
      |> apply_close_history_cursor(cursor)
      |> order_by([s], desc: s.shop_date, desc: s.id)
      |> limit(^(limit + 1))
      |> preload(:closed_by_user)

    rows = Repo.all(query)
    has_next_page? = length(rows) > limit
    closes = Enum.take(rows, limit)

    next_cursor =
      if has_next_page? do
        case List.last(closes) do
          %ShiftClose{shop_date: %Date{} = shop_date, id: id} -> %{date: shop_date, id: id}
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

  defp normalize_close_history_cursor(%{date: %Date{} = date, id: id}) when is_integer(id),
    do: %{date: date, id: id}

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

  defp apply_close_history_cursor(query, %{date: date, id: id}) do
    from(s in query, where: s.shop_date < ^date or (s.shop_date == ^date and s.id < ^id))
  end

  def get_close(id) when is_integer(id) do
    ShiftClose
    |> Tenancy.scope_to_branch()
    |> preload(:closed_by_user)
    |> Repo.get(id)
  end

  def get_close_for_session(id) when is_integer(id) do
    ShiftClose
    |> Tenancy.scope_to_branch()
    |> where([s], s.shop_session_id == ^id)
    |> Repo.one()
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
  Shop session sales gate: `:open`, `:not_open`, or `:closed`.
  """
  def shop_day_status do
    cond do
      current_session() -> :open
      get_todays_close() -> :closed
      true -> :not_open
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
    do: "Shop is closed. Record opening cash before selling."

  def selling_blocked_message(_), do: "Selling is not available right now."

  @doc """
  The current session's opening cash, if recorded.
  """
  def get_todays_open do
    current_session()
  end

  def current_session do
    ShopDayOpen
    |> Tenancy.scope_to_branch()
    |> where([o], o.session_active == true)
    |> preload(:opened_by_user)
    |> Repo.one()
  end

  def lock_session! do
    key = :erlang.phash2({:espreso_shop_session, Tenancy.current_branch_id()})
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [key])
    :ok
  end

  def session_for_write! do
    lock_session!()

    case current_session() do
      %ShopDayOpen{} = session -> session
      nil -> Repo.rollback(if(get_todays_close(), do: :shop_day_closed, else: :shop_not_open))
    end
  end

  def get_open_for_date(%Date{} = shop_date) do
    ShopDayOpen
    |> Tenancy.scope_to_branch()
    |> where([o], o.shop_date == ^shop_date)
    |> order_by([o], desc: o.opened_at, desc: o.id)
    |> limit(1)
    |> preload(:opened_by_user)
    |> Repo.one()
  end

  @doc """
  Records opening drawer cash for a new session.

  Only one session may be open for a branch at a time.
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
    opening_cash =
      parse_required_decimal(Map.get(attrs, :opening_cash) || Map.get(attrs, "opening_cash"))

    notes = normalize_notes(Map.get(attrs, :notes) || Map.get(attrs, "notes"))

    if is_nil(opening_cash) do
      {:error, :opening_cash_required}
    else
      result =
        Repo.transaction(fn ->
          lock_session!()

          if current_session() do
            Repo.rollback(:already_open)
          end

          opened_at = DateTime.utc_now() |> DateTime.truncate(:second)
          shop_date = opened_at |> DateTime.add(8 * 60 * 60, :second) |> DateTime.to_date()

          %ShopDayOpen{}
          |> ShopDayOpen.changeset(%{
            shop_date: shop_date,
            opening_cash: opening_cash,
            opened_at: opened_at,
            opened_by_user_id: user.id,
            notes: notes,
            session_active: true,
            tenant_id: Tenancy.current_tenant_id(),
            branch_id: Tenancy.current_branch_id()
          })
          |> Repo.insert()
          |> case do
            {:ok, open} ->
              Repo.preload(open, :opened_by_user)

            {:error, %Ecto.Changeset{errors: errors} = changeset} ->
              if Keyword.has_key?(errors, :session_active) do
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
  def expected_drawer_cash(opening_cash, cash_sales, cash_out_total, petty_cash_transfer \\ 0) do
    Decimal.sub(
      Decimal.add(decimalize_money(opening_cash), decimalize_money(cash_sales)),
      Decimal.add(
        decimalize_money(cash_out_total),
        decimalize_money(petty_cash_transfer)
      )
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
  Records a close for the currently open session.

  Snapshots the session's paid totals, cash movements, and business date.

  Baristas must be the last active StaffShift. Closing does not end attendance
  shifts; staff time out separately.
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
    counted_cash =
      parse_required_decimal(Map.get(attrs, :counted_cash) || Map.get(attrs, "counted_cash"))

    notes = normalize_notes(Map.get(attrs, :notes) || Map.get(attrs, "notes"))

    petty_cash_counted =
      parse_optional_decimal(
        Map.get(attrs, :petty_cash_counted) || Map.get(attrs, "petty_cash_counted")
      )

    petty_cash_notes =
      normalize_notes(Map.get(attrs, :petty_cash_notes) || Map.get(attrs, "petty_cash_notes"))

    if is_nil(counted_cash) do
      {:error, :counted_cash_required}
    else
      result =
        Repo.transaction(fn ->
          lock_session!()

          opening =
            case current_session() do
              %ShopDayOpen{} = session ->
                session

              nil ->
                Repo.rollback(if(get_todays_close(), do: :already_closed, else: :shop_not_open))
            end

          closed_at = DateTime.utc_now() |> DateTime.truncate(:second)
          shop_date = opening.shop_date
          breakdown = Orders.paid_breakdown_for_session(opening)

          if mode == :barista do
            StaffShifts.assert_last_active_closer!(user)
          end

          opening_cash = opening.opening_cash
          cash_sales = cash_sales_total(breakdown)
          cash_out_total = CashOuts.total_for_session(opening.id)
          petty_cash_expenses = PettyCash.total_for_session(opening.id)

          petty_cash_expected =
            Decimal.sub(PettyCash.float(), petty_cash_expenses) |> Decimal.round(2)

          counted_petty_cash = petty_cash_counted || petty_cash_expected
          petty_cash_variance = drawer_variance(counted_petty_cash, petty_cash_expected)

          petty_cash_transfer =
            Decimal.sub(PettyCash.float(), counted_petty_cash) |> Decimal.round(2)

          if petty_cash_counted && not Decimal.equal?(petty_cash_variance, 0) &&
               is_nil(petty_cash_notes) do
            Repo.rollback(:petty_cash_notes_required)
          end

          expected_cash =
            expected_drawer_cash(
              opening_cash,
              cash_sales,
              cash_out_total,
              petty_cash_transfer
            )

          variance = drawer_variance(counted_cash, expected_cash)

          close =
            %ShiftClose{}
            |> ShiftClose.changeset(%{
              shop_date: shop_date,
              shop_session_id: opening.id,
              system_total: breakdown.total,
              system_count: breakdown.count,
              by_via: serialize_by_via(breakdown.by_via),
              counted_cash: counted_cash,
              opening_cash: opening_cash,
              expected_cash: expected_cash,
              variance: variance,
              notes: notes,
              petty_cash_counted: counted_petty_cash,
              petty_cash_expected: petty_cash_expected,
              petty_cash_variance: petty_cash_variance,
              petty_cash_transfer: petty_cash_transfer,
              petty_cash_notes: petty_cash_notes,
              closed_by_user_id: user.id,
              closed_at: closed_at,
              tenant_id: Tenancy.current_tenant_id(),
              branch_id: Tenancy.current_branch_id()
            })
            |> Repo.insert()
            |> case do
              {:ok, close} ->
                close

              {:error, %Ecto.Changeset{errors: errors} = changeset} ->
                if Keyword.has_key?(errors, :shop_session_id) do
                  Repo.rollback(:already_closed)
                else
                  Repo.rollback(changeset)
                end
            end

          opening |> Ecto.Changeset.change(session_active: false) |> Repo.update!()
          Repo.preload(close, :closed_by_user)
        end)

      case result do
        {:ok, %ShiftClose{} = close} -> {:ok, close}
        {:error, :already_closed} -> {:error, :already_closed}
        {:error, :other_staff_active} -> {:error, :other_staff_active}
        {:error, :not_on_shift} -> {:error, :not_on_shift}
        {:error, :petty_cash_notes_required} -> {:error, :petty_cash_notes_required}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
        {:error, reason} -> {:error, reason}
      end
    end
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
