defmodule Espreso.PettyCash do
  @moduledoc """
  Petty-cash purchases paid from the separate shop float, not the sales drawer.
  """

  import Ecto.Query

  alias Espreso.Accounts.User
  alias Espreso.Orders
  alias Espreso.PettyCash.PettyCashEntry
  alias Espreso.Repo
  alias Espreso.Shifts
  alias Espreso.StaffShifts
  alias Espreso.Tenancy

  @float Decimal.new("500.00")

  def float, do: @float

  def can_access?(%User{active: true, role: role}) when role in ~w(barista manager owner),
    do: true

  def can_access?(_), do: false

  def can_void?(%User{active: true, role: role}) when role in ~w(manager owner), do: true
  def can_void?(_), do: false

  def create_entry(%User{} = actor, attrs) when is_map(attrs) do
    with :ok <- authorize_create(actor),
         :ok <- Shifts.assert_selling_allowed(),
         {:ok, staff_shift_id} <- resolve_staff_shift_id(actor) do
      shop_date = Orders.shop_date_today()

      changeset =
        %PettyCashEntry{}
        |> PettyCashEntry.create_changeset(%{
          amount: attr(attrs, :amount),
          category: attr(attrs, :category),
          note: attr(attrs, :note),
          recorded_at: utc_now(),
          shop_date: shop_date,
          status: "recorded",
          created_by_user_id: actor.id,
          staff_shift_id: staff_shift_id,
          tenant_id: actor.tenant_id,
          branch_id: actor.branch_id
        })

      result =
        Repo.transaction(fn ->
          lock_petty_cash!(actor.branch_id, shop_date)

          if changeset.valid? do
            remaining =
              Decimal.sub(@float, total_for_shop_date(shop_date))
              |> Decimal.max(Decimal.new("0"))

            if Decimal.compare(Ecto.Changeset.get_field(changeset, :amount), remaining) == :gt do
              Repo.rollback(:insufficient_petty_cash)
            end
          else
            Repo.rollback(changeset)
          end

          case Repo.insert(changeset) do
            {:ok, entry} -> Repo.preload(entry, [:created_by_user, :staff_shift])
            {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
          end
        end)

      case result do
        {:ok, entry} -> {:ok, entry}
        {:error, :insufficient_petty_cash} -> {:error, :insufficient_petty_cash}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def list_for_shop_date(%Date{} = shop_date) do
    list_for_shop_dates(shop_date, shop_date)
  end

  def list_for_shop_dates(%Date{} = from_date, %Date{} = to_date) do
    PettyCashEntry
    |> Tenancy.scope_to_branch()
    |> where([entry], entry.shop_date >= ^from_date and entry.shop_date <= ^to_date)
    |> order_by([entry], desc: entry.recorded_at, desc: entry.id)
    |> preload([:created_by_user])
    |> Repo.all()
  end

  def list_recent_history do
    today = Orders.shop_date_today()
    start_date = Date.add(today, -30)

    PettyCashEntry
    |> Tenancy.scope_to_branch()
    |> where([entry], entry.shop_date >= ^start_date and entry.shop_date < ^today)
    |> order_by([entry], desc: entry.shop_date, desc: entry.recorded_at, desc: entry.id)
    |> limit(100)
    |> preload([:created_by_user])
    |> Repo.all()
  end

  def total_for_shop_date(%Date{} = shop_date) do
    total =
      PettyCashEntry
      |> Tenancy.scope_to_branch()
      |> where([entry], entry.shop_date == ^shop_date and entry.status == "recorded")
      |> select([entry], sum(entry.amount))
      |> Repo.one()

    total || Decimal.new("0")
  end

  def void_entry(%PettyCashEntry{} = entry, %User{} = actor, reason)
      when is_binary(reason) do
    with :ok <- authorize_void(actor),
         :ok <- ensure_shop_day_open(entry.shop_date),
         :ok <- ensure_recorded(entry) do
      entry
      |> PettyCashEntry.void_changeset(%{
        status: "voided",
        voided_at: utc_now(),
        voided_by_user_id: actor.id,
        void_reason: reason
      })
      |> Repo.update()
    end
  end

  defp attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp authorize_create(%User{} = user) do
    if can_access?(user), do: :ok, else: {:error, :unauthorized}
  end

  defp authorize_void(%User{} = user) do
    if can_void?(user), do: :ok, else: {:error, :unauthorized}
  end

  defp ensure_shop_day_open(%Date{} = shop_date) do
    if Shifts.get_close_for_date(shop_date), do: {:error, :shop_day_closed}, else: :ok
  end

  defp ensure_recorded(%PettyCashEntry{status: "recorded"}), do: :ok
  defp ensure_recorded(%PettyCashEntry{}), do: {:error, :already_voided}

  defp lock_petty_cash!(branch_id, %Date{} = shop_date) do
    key = :erlang.phash2({:espreso_petty_cash, branch_id, Date.to_iso8601(shop_date)})
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [key])
    :ok
  end

  defp resolve_staff_shift_id(%User{role: "barista"} = user) do
    case StaffShifts.get_open_shift(user) do
      %{id: id} -> {:ok, id}
      nil -> {:error, :not_on_shift}
    end
  end

  defp resolve_staff_shift_id(%User{role: role}) when role in ~w(manager owner), do: {:ok, nil}
  defp resolve_staff_shift_id(_), do: {:error, :unauthorized}

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
