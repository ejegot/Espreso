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
  Blocked when today's shop day is already sealed by ShiftClose.
  """
  def create_cash_out(%User{} = actor, attrs) when is_map(attrs) do
    with :ok <- authorize_create(actor),
         :ok <- ensure_shop_day_open(Orders.shop_date_today()),
         {:ok, staff_shift_id} <- resolve_staff_shift_id(actor) do
      recorded_at = utc_now()
      shop_date = Orders.shop_date_today()

      %CashOut{}
      |> CashOut.create_changeset(%{
        amount: Map.get(attrs, :amount) || Map.get(attrs, "amount"),
        category: Map.get(attrs, :category) || Map.get(attrs, "category"),
        note: Map.get(attrs, :note) || Map.get(attrs, "note"),
        recorded_at: recorded_at,
        shop_date: shop_date,
        status: "recorded",
        created_by_user_id: actor.id,
        staff_shift_id: staff_shift_id
      })
      |> Repo.insert()
      |> case do
        {:ok, cash_out} ->
          {:ok, Repo.preload(cash_out, [:created_by_user, :staff_shift])}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Lists Cash Outs for a Manila shop date, newest first.

  Preloads `:created_by_user`. Includes recorded and voided rows.
  """
  def list_cash_outs_for_shop_date(%Date{} = shop_date) do
    CashOut
    |> where([c], c.shop_date == ^shop_date)
    |> order_by([c], desc: c.recorded_at, desc: c.id)
    |> preload([:created_by_user])
    |> Repo.all()
  end

  @doc """
  Sum of non-voided (`status == "recorded"`) Cash Out amounts for a shop date.
  """
  def total_for_shop_date(%Date{} = shop_date) do
    total =
      CashOut
      |> where([c], c.shop_date == ^shop_date and c.status == "recorded")
      |> select([c], sum(c.amount))
      |> Repo.one()

    decimalize(total)
  end

  @doc """
  Non-voided Cash Outs for a shop date, newest first.
  """
  def list_recorded_for_shop_date(%Date{} = shop_date) do
    CashOut
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
    with :ok <- authorize_void(actor),
         :ok <- ensure_shop_day_open(cash_out.shop_date),
         :ok <- ensure_recorded(cash_out) do
      cash_out
      |> CashOut.void_changeset(%{
        status: "voided",
        voided_at: utc_now(),
        voided_by_user_id: actor.id,
        void_reason: reason
      })
      |> Repo.update()
      |> case do
        {:ok, voided} ->
          {:ok, Repo.preload(voided, [:created_by_user, :voided_by_user], force: true)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, changeset}
      end
    end
  end

  defp authorize_create(%User{} = user) do
    if can_access?(user), do: :ok, else: {:error, :unauthorized}
  end

  defp authorize_void(%User{} = user) do
    if can_void?(user), do: :ok, else: {:error, :unauthorized}
  end

  defp ensure_shop_day_open(%Date{} = shop_date) do
    case Shifts.get_close_for_date(shop_date) do
      nil -> :ok
      %Shifts.ShiftClose{} -> {:error, :shop_day_closed}
    end
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
