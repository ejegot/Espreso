defmodule Espreso.Shifts do
  @moduledoc """
  Light end-of-day shift close snapshots for CoffeeSpot.
  """

  import Ecto.Query

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.Orders
  alias Espreso.Repo
  alias Espreso.Shifts.ShiftClose

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
  Records a shift close for today's shop date.

  Snapshots system paid totals from `Orders.todays_paid_breakdown/0`.
  One close per shop day.
  """
  def record_close(%User{} = user, attrs \\ %{}) do
    with :ok <- Authorization.authorize(user, :reports) do
      do_record_close(user, attrs)
    end
  end

  defp do_record_close(%User{} = user, attrs) do
    breakdown = Orders.todays_paid_breakdown()
    shop_date = breakdown.shop_date

    case get_close_for_date(shop_date) do
      %ShiftClose{} ->
        {:error, :already_closed}

      nil ->
        counted_cash = parse_optional_decimal(Map.get(attrs, :counted_cash) || Map.get(attrs, "counted_cash"))
        notes = normalize_notes(Map.get(attrs, :notes) || Map.get(attrs, "notes"))

        %ShiftClose{}
        |> ShiftClose.changeset(%{
          shop_date: shop_date,
          system_total: breakdown.total,
          system_count: breakdown.count,
          by_via: serialize_by_via(breakdown.by_via),
          counted_cash: counted_cash,
          notes: notes,
          closed_by_user_id: user.id,
          closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()
        |> case do
          {:ok, close} -> {:ok, Repo.preload(close, :closed_by_user)}
          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            if Keyword.has_key?(errors, :shop_date) do
              {:error, :already_closed}
            else
              {:error, changeset}
            end
        end
    end
  end

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
