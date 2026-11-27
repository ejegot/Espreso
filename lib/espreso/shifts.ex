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
  alias Espreso.Orders.Order
  alias Espreso.PettyCash
  alias Espreso.Repo
  alias Espreso.Shifts.ShopDayOpen
  alias Espreso.Shifts.ShopSessionAdjustment
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

  def list_adjustments_for_session(session_id) when is_integer(session_id) do
    ShopSessionAdjustment
    |> Tenancy.scope_to_branch()
    |> where([a], a.shop_session_id == ^session_id)
    |> order_by([a], asc: a.inserted_at, asc: a.id)
    |> preload([:original_order, :recorded_by_user])
    |> Repo.all()
  end

  def list_adjustments_for_session(_), do: []

  def list_adjustments_for_shop_dates(%Date{} = from_date, %Date{} = to_date) do
    ShopSessionAdjustment
    |> Tenancy.scope_to_branch()
    |> join(:inner, [a], session in assoc(a, :shop_session))
    |> where([_a, session], session.shop_date >= ^from_date and session.shop_date <= ^to_date)
    |> order_by([a, session], asc: session.shop_date, asc: a.inserted_at, asc: a.id)
    |> preload([:original_order, :recorded_by_user, :shop_session])
    |> Repo.all()
  end

  def adjustment_for_order(order_id) when is_integer(order_id) do
    ShopSessionAdjustment
    |> Tenancy.scope_to_branch()
    |> where([a], a.original_order_id == ^order_id)
    |> preload([:original_order, :recorded_by_user, :shop_session])
    |> Repo.one()
  end

  def adjustment_for_order(_), do: nil

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

  def close_preview do
    Repo.transaction(fn ->
      lock_session!()

      case current_session() do
        %ShopDayOpen{} = session ->
          settlement_snapshot(session)

        nil ->
          Repo.rollback(if(get_todays_close(), do: :shop_day_closed, else: :shop_not_open))
      end
    end)
    |> case do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, reason} -> {:error, reason}
    end
  end

  defp settlement_snapshot(session) do
    cash_outs =
      session.id
      |> CashOuts.list_for_session()
      |> Enum.filter(&(&1.status == "recorded"))
      |> Enum.map(&{&1.id, &1.amount})
      |> Enum.sort()

    petty_cash_entries =
      session.id
      |> PettyCash.list_for_session()
      |> Enum.filter(&(&1.status == "recorded"))
      |> Enum.map(&{&1.id, &1.amount})
      |> Enum.sort()

    adjustment_rows = list_adjustments_for_session(session.id)

    adjustments =
      Enum.map(adjustment_rows, &{&1.id, &1.sales_impact, &1.drawer_impact, &1.payment_breakdown})

    adjustment_cash_impact =
      Enum.reduce(adjustment_rows, Decimal.new("0"), fn adjustment, total ->
        Decimal.add(total, adjustment.drawer_impact)
      end)
      |> Decimal.round(2)

    %{
      session_id: session.id,
      opening_cash: session.opening_cash,
      breakdown: Orders.paid_breakdown_for_session(session),
      cash_sales: Orders.cash_sales_for_session(session),
      adjustments: adjustments,
      adjustment_cash_impact: adjustment_cash_impact,
      cash_outs: cash_outs,
      petty_cash_entries: petty_cash_entries
    }
  end

  def record_post_close_adjustment(%Order{id: id}, %User{} = user, attrs)
      when is_integer(id) and is_map(attrs) do
    if Authorization.can?(user, :reports) do
      do_record_post_close_adjustment(id, user, attrs)
    else
      {:error, :unauthorized}
    end
  end

  def record_post_close_adjustment(%Order{}, _user, _attrs), do: {:error, :not_found}

  def record_post_close_adjustment(_, _, _), do: {:error, :not_found}

  defp do_record_post_close_adjustment(order_id, user, attrs) do
    kind = attr(attrs, :kind) |> to_string()
    reason = attr(attrs, :reason) |> normalize_notes()
    cash_refund = parse_optional_decimal(attr(attrs, :cash_refund))

    cond do
      kind not in ShopSessionAdjustment.kinds() ->
        {:error, :invalid_adjustment_kind}

      is_nil(reason) or String.length(reason) < 2 ->
        {:error, :adjustment_reason_required}

      kind == "refund" and is_nil(cash_refund) ->
        {:error, :drawer_impact_required}

      not is_nil(cash_refund) and Decimal.compare(cash_refund, 0) == :lt ->
        {:error, :invalid_drawer_impact}

      kind == "duplicate_void" and not is_nil(cash_refund) and
          not Decimal.equal?(cash_refund, 0) ->
        {:error, :invalid_drawer_impact}

      true ->
        result =
          Repo.transaction(fn ->
            session = session_for_write!()

            order =
              Order
              |> Tenancy.scope_to_branch()
              |> where(
                [o],
                o.id == ^order_id and o.payment_status == "paid" and
                  not is_nil(o.settled_at) and is_nil(o.refunded_at) and
                  is_nil(o.duplicate_voided_at)
              )
              |> preload(:payment_splits)
              |> Repo.one()

            cond do
              is_nil(order) ->
                Repo.rollback(:not_eligible)

              order.shop_session_id == session.id ->
                Repo.rollback(:session_not_closed)

              not closed_order_before_session?(order, session) ->
                Repo.rollback(:session_not_closed)

              adjustment_for_order(order.id) ->
                Repo.rollback(:already_adjusted)

              kind == "refund" and Decimal.compare(cash_refund, order.total) == :gt ->
                Repo.rollback(:invalid_drawer_impact)

              true ->
                payment_breakdown = adjustment_payment_breakdown(order)
                sales_impact = Decimal.negate(order.total) |> Decimal.round(2)

                drawer_impact =
                  Decimal.negate(cash_refund || Decimal.new("0")) |> Decimal.round(2)

                %ShopSessionAdjustment{}
                |> ShopSessionAdjustment.changeset(%{
                  kind: kind,
                  reason: reason,
                  payment_method: adjustment_payment_method(order),
                  payment_breakdown: payment_breakdown,
                  sales_impact: sales_impact,
                  drawer_impact: drawer_impact,
                  original_order_id: order.id,
                  shop_session_id: session.id,
                  recorded_by_user_id: user.id,
                  tenant_id: Tenancy.current_tenant_id(),
                  branch_id: Tenancy.current_branch_id()
                })
                |> Repo.insert()
                |> case do
                  {:ok, adjustment} ->
                    Repo.preload(adjustment, [:original_order, :recorded_by_user, :shop_session])

                  {:error, changeset} ->
                    if Keyword.has_key?(changeset.errors, :original_order_id) do
                      Repo.rollback(:already_adjusted)
                    else
                      Repo.rollback(changeset)
                    end
                end
            end
          end)

        case result do
          {:ok, %ShopSessionAdjustment{} = adjustment} ->
            Phoenix.PubSub.broadcast(
              Espreso.PubSub,
              "orders",
              {:order_changed, adjustment.original_order}
            )

            {:ok, adjustment}

          {:error, reason} when reason in [:shop_not_open, :shop_day_closed] ->
            {:error, reason}

          {:error, reason}
          when reason in [:not_eligible, :session_not_closed, :already_adjusted] ->
            {:error, reason}

          {:error, reason} when reason == :invalid_drawer_impact ->
            {:error, reason}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp closed_order_before_session?(%Order{shop_session_id: nil, settled_at: settled_at}, session) do
    DateTime.compare(settled_at, session.opened_at) == :lt
  end

  defp closed_order_before_session?(%Order{shop_session_id: order_session_id}, session) do
    if order_session_id != session.id do
      ShiftClose
      |> Tenancy.scope_to_branch()
      |> where([close], close.shop_session_id == ^order_session_id)
      |> Repo.exists?()
    else
      false
    end
  end

  defp adjustment_payment_method(%Order{payment_splits: splits}) when splits != [],
    do: "split"

  defp adjustment_payment_method(%Order{paid_via: paid_via})
       when paid_via in ["cash", "gcash", "maya", "counter", "paymongo"],
       do: paid_via

  defp adjustment_payment_method(_), do: "counter"

  defp adjustment_payment_breakdown(%Order{payment_splits: splits}) when splits != [] do
    Map.new(splits, fn split ->
      {split.paid_via, Decimal.negate(split.amount) |> Decimal.round(2) |> Decimal.to_string()}
    end)
  end

  defp adjustment_payment_breakdown(%Order{} = order) do
    via = order.paid_via || "counter"
    %{via => Decimal.negate(order.total) |> Decimal.round(2) |> Decimal.to_string()}
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
  def expected_drawer_cash(
        opening_cash,
        cash_sales,
        cash_out_total,
        petty_cash_transfer \\ 0,
        adjustment_cash_impact \\ 0
      ) do
    Decimal.sub(
      Decimal.add(
        Decimal.add(decimalize_money(opening_cash), decimalize_money(cash_sales)),
        decimalize_money(adjustment_cash_impact)
      ),
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

  def cash_sales_total(%{cash_sales: cash_sales}) when not is_nil(cash_sales),
    do: decimalize_money(cash_sales)

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
    |> Decimal.add(Map.get(close, :adjustment_cash_impact) || Decimal.new("0"))
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
  def record_close(%User{} = user, attrs \\ %{}, opts \\ []) do
    cond do
      Authorization.can?(user, :reports) ->
        do_record_close(user, attrs, :manager, opts)

      barista?(user) ->
        do_record_close(user, attrs, :barista, opts)

      true ->
        {:error, :unauthorized}
    end
  end

  defp do_record_close(%User{} = user, attrs, mode, opts) do
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

          expected_session_id = Keyword.get(opts, :expected_session_id)

          if expected_session_id && opening.id != expected_session_id do
            Repo.rollback(:session_changed)
          end

          snapshot = settlement_snapshot(opening)

          if reviewed_snapshot = Keyword.get(opts, :reviewed_snapshot) do
            if snapshot != reviewed_snapshot, do: Repo.rollback(:settlement_changed)
          end

          closed_at = DateTime.utc_now() |> DateTime.truncate(:second)
          shop_date = opening.shop_date
          breakdown = snapshot.breakdown

          if mode == :barista do
            StaffShifts.assert_last_active_closer!(user)
          end

          opening_cash = opening.opening_cash
          cash_sales = snapshot.cash_sales
          adjustment_cash_impact = snapshot.adjustment_cash_impact
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
              petty_cash_transfer,
              adjustment_cash_impact
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
              cash_sales: cash_sales,
              adjustment_cash_impact: adjustment_cash_impact,
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
        {:error, :session_changed} -> {:error, :session_changed}
        {:error, :settlement_changed} -> {:error, :settlement_changed}
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

  defp attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

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
