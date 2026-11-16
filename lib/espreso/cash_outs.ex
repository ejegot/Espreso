defmodule Espreso.CashOuts do
  @moduledoc """
  Physical cash drawer withdrawals for legitimate shop expenses.

  Separate from Orders / POS sales and from shop-day `Espreso.Shifts` / ShiftClose.
  """

  import Ecto.Query

  alias Espreso.Accounts.User
  alias Espreso.CashOuts.CashOut
  alias Espreso.Orders
  alias Espreso.Repo
  alias Espreso.Shifts
  alias Espreso.StaffShifts
  alias Espreso.Tenancy

  @doc """
  True when the user may open the Cash Out screen (barista / manager / owner).
  """
  def can_access?(%User{active: true, role: role}) when role in ~w(barista manager owner),
    do: true

  def can_access?(_), do: false

  @doc """
  True when the user may void a Cash Out (manager / owner).
  """
  def can_void?(%User{active: true, role: role}) when role in ~w(manager owner), do: true
  def can_void?(_), do: false

  @doc """
  Records a Cash Out for the actor.

  Baristas must have an open StaffShift. Manager/owner may record without one.
  Blocked until opening cash is recorded, and after the shop day is sealed.
  """
  def create_cash_out(%User{} = actor, attrs) when is_map(attrs) do
    with :ok <- authorize_create(actor),
         :ok <- Shifts.assert_selling_allowed(),
         {:ok, staff_shift_id} <- resolve_staff_shift_id(actor) do
      Repo.transaction(fn ->
        session = Shifts.session_for_write!()

        %CashOut{}
        |> CashOut.create_changeset(%{
          amount: Map.get(attrs, :amount) || Map.get(attrs, "amount"),
          category: Map.get(attrs, :category) || Map.get(attrs, "category"),
          note: Map.get(attrs, :note) || Map.get(attrs, "note"),
          recorded_at: utc_now(),
          shop_date: session.shop_date,
          shop_session_id: session.id,
          status: "recorded",
          created_by_user_id: actor.id,
          staff_shift_id: staff_shift_id,
          tenant_id: session.tenant_id,
          branch_id: session.branch_id
        })
        |> Repo.insert()
        |> case do
          {:ok, cash_out} -> Repo.preload(cash_out, [:created_by_user, :staff_shift])
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end
  end

  @doc """
  Lists Cash Outs for a Manila shop date, newest first.

  Preloads `:created_by_user`. Includes recorded and voided rows.
  """
  def list_cash_outs_for_shop_date(%Date{} = shop_date) do
    CashOut
    |> Tenancy.scope_to_branch()
    |> where([c], c.shop_date == ^shop_date)
    |> order_by([c], desc: c.recorded_at, desc: c.id)
    |> preload([:created_by_user])
    |> Repo.all()
  end

  def list_for_session(session_id) when is_integer(session_id) do
    CashOut
    |> Tenancy.scope_to_branch()
    |> where([c], c.shop_session_id == ^session_id)
    |> order_by([c], desc: c.recorded_at, desc: c.id)
    |> preload(:created_by_user)
    |> Repo.all()
  end

  @doc """
  Cash Outs (recorded and voided) whose `shop_date` falls in the inclusive range.
  """
  def list_cash_outs_for_shop_dates(%Date{} = from_date, %Date{} = to_date) do
    CashOut
    |> Tenancy.scope_to_branch()
    |> where([c], c.shop_date >= ^from_date and c.shop_date <= ^to_date)
    |> order_by([c], asc: c.shop_date, desc: c.recorded_at, desc: c.id)
    |> preload([:created_by_user])
    |> Repo.all()
  end

  @cash_out_history_page_size 25

  @doc """
  Read-only Cash Out history grouped by Manila shop date, newest day first.

  Excludes the active session but includes earlier closed sessions on the same
  business date. Optional `:cursor` continues with older dates.

  Each day includes all rows (recorded + voided) and the recorded-only total
  via the existing day-scoped helpers.

  Optional `opts`:
  - `:limit` — page size (default #{@cash_out_history_page_size}, clamped 1..100)
  - `:cursor` — last visible `shop_date` from the previous page

  Returns `%{days, has_next_page, next_cursor}`.
  """
  def list_cash_out_history(opts \\ []) when is_list(opts) do
    limit =
      opts
      |> Keyword.get(
        :limit,
        Application.get_env(:espreso, :cash_out_history_page_size, @cash_out_history_page_size)
      )
      |> cash_out_history_page_limit()

    session = Shifts.current_session()
    today = if session, do: session.shop_date, else: Orders.shop_date_today()
    cursor = normalize_cash_out_history_cursor(Keyword.get(opts, :cursor))
    upper_bound = cursor || today

    base_query = Tenancy.scope_to_branch(CashOut)

    base_query =
      cond do
        cursor ->
          where(base_query, [c], c.shop_date < ^upper_bound)

        session ->
          where(
            base_query,
            [c],
            c.shop_date < ^upper_bound or
              (c.shop_date == ^upper_bound and
                 (is_nil(c.shop_session_id) or c.shop_session_id != ^session.id))
          )

        true ->
          where(
            base_query,
            [c],
            c.shop_date <= ^upper_bound
          )
      end

    shop_dates =
      from(c in base_query,
        group_by: c.shop_date,
        select: c.shop_date,
        order_by: [desc: c.shop_date],
        limit: ^(limit + 1)
      )
      |> Repo.all()

    has_next_page? = length(shop_dates) > limit
    page_dates = Enum.take(shop_dates, limit)

    days =
      Enum.map(page_dates, fn shop_date ->
        cash_outs =
          list_cash_outs_for_shop_date(shop_date)
          |> Enum.reject(fn cash_out ->
            session && cash_out.shop_session_id == session.id
          end)

        %{
          shop_date: shop_date,
          cash_outs: cash_outs,
          total:
            cash_outs
            |> Enum.filter(&(&1.status == "recorded"))
            |> Enum.reduce(Decimal.new("0"), &Decimal.add(&1.amount, &2))
        }
      end)

    next_cursor =
      if has_next_page? do
        List.last(page_dates)
      else
        nil
      end

    %{
      days: days,
      has_next_page: has_next_page?,
      next_cursor: next_cursor
    }
  end

  defp cash_out_history_page_limit(limit) when is_integer(limit) and limit > 0,
    do: min(limit, 100)

  defp cash_out_history_page_limit(_), do: @cash_out_history_page_size

  defp normalize_cash_out_history_cursor(%Date{} = shop_date), do: shop_date

  defp normalize_cash_out_history_cursor(shop_date) when is_binary(shop_date) do
    case Date.from_iso8601(shop_date) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp normalize_cash_out_history_cursor(_), do: nil

  @doc """
  Sum of non-voided (`status == "recorded"`) Cash Out amounts for a shop date.
  """
  def total_for_shop_date(%Date{} = shop_date) do
    total =
      CashOut
      |> Tenancy.scope_to_branch()
      |> where([c], c.shop_date == ^shop_date and c.status == "recorded")
      |> select([c], sum(c.amount))
      |> Repo.one()

    decimalize(total)
  end

  def total_for_session(session_id) when is_integer(session_id) do
    CashOut
    |> Tenancy.scope_to_branch()
    |> where([c], c.shop_session_id == ^session_id and c.status == "recorded")
    |> select([c], sum(c.amount))
    |> Repo.one()
    |> decimalize()
  end

  @doc """
  Non-voided Cash Outs for a shop date, newest first.
  """
  def list_recorded_for_shop_date(%Date{} = shop_date) do
    CashOut
    |> Tenancy.scope_to_branch()
    |> where([c], c.shop_date == ^shop_date and c.status == "recorded")
    |> order_by([c], desc: c.recorded_at, desc: c.id)
    |> preload([:created_by_user])
    |> Repo.all()
  end

  @doc """
  Voids a recorded Cash Out. Manager/owner only. Blocked when shop day is sealed.
  """
  def void_cash_out(%CashOut{} = cash_out, %User{} = actor, reason)
      when is_binary(reason) or is_nil(reason) do
    with :ok <- authorize_void(actor) do
      Repo.transaction(fn ->
        session = Shifts.session_for_write!()

        current =
          case CashOut |> Tenancy.scope_to_branch() |> Repo.get(cash_out.id) do
            nil -> Repo.rollback(:not_found)
            row -> row
          end

        if current.shop_session_id != session.id, do: Repo.rollback(:shop_day_closed)
        if ensure_recorded(current) != :ok, do: Repo.rollback(:already_voided)

        current
        |> CashOut.void_changeset(%{
          status: "voided",
          voided_at: utc_now(),
          voided_by_user_id: actor.id,
          void_reason: reason
        })
        |> Repo.update()
        |> case do
          {:ok, voided} -> Repo.preload(voided, [:created_by_user, :voided_by_user], force: true)
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end
  end

  defp authorize_create(%User{} = user) do
    if can_access?(user), do: :ok, else: {:error, :unauthorized}
  end

  defp authorize_void(%User{} = user) do
    if can_void?(user), do: :ok, else: {:error, :unauthorized}
  end

  defp ensure_recorded(%CashOut{status: "recorded"}), do: :ok
  defp ensure_recorded(%CashOut{}), do: {:error, :already_voided}

  defp resolve_staff_shift_id(%User{role: "barista"} = user) do
    case StaffShifts.get_open_shift(user) do
      %{id: id} -> {:ok, id}
      nil -> {:error, :not_on_shift}
    end
  end

  defp resolve_staff_shift_id(%User{role: role}) when role in ~w(manager owner), do: {:ok, nil}
  defp resolve_staff_shift_id(_), do: {:error, :unauthorized}

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp decimalize(nil), do: Decimal.new("0")
  defp decimalize(%Decimal{} = value), do: value
  defp decimalize(value) when is_integer(value), do: Decimal.new(value)
  defp decimalize(value) when is_float(value), do: Decimal.from_float(value)
  defp decimalize(value) when is_binary(value), do: Decimal.new(value)
  defp decimalize(_), do: Decimal.new("0")
end
