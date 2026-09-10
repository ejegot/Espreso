defmodule Espreso.CashOuts.CashOut do
  @moduledoc """
  Physical cash drawer withdrawal for a legitimate shop expense.

  Separate from Orders / POS sales and from shop-day `ShiftClose`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Accounts.User
  alias Espreso.StaffShifts.StaffShift

  @categories ~w(Ingredients Supplies Cleaning Other)
  @statuses ~w(recorded voided)

  schema "cash_outs" do
    field :amount, :decimal
    field :category, :string
    field :note, :string
    field :recorded_at, :utc_datetime
    field :shop_date, :date
    field :status, :string, default: "recorded"
    field :voided_at, :utc_datetime
    field :void_reason, :string

    belongs_to :created_by_user, User, foreign_key: :created_by_user_id
    belongs_to :staff_shift, StaffShift
    belongs_to :voided_by_user, User, foreign_key: :voided_by_user_id

    timestamps(type: :utc_datetime)
  end

  def categories, do: @categories
  def statuses, do: @statuses

  def create_changeset(cash_out, attrs) do
    cash_out
    |> cast(attrs, [
      :amount,
      :category,
      :note,
      :recorded_at,
      :shop_date,
      :status,
      :created_by_user_id,
      :staff_shift_id
    ])
    |> validate_required([
      :amount,
      :category,
      :recorded_at,
      :shop_date,
      :status,
      :created_by_user_id
    ])
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:amount, greater_than: 0)
    |> update_change(:note, &normalize_optional_text/1)
    |> foreign_key_constraint(:created_by_user_id)
    |> foreign_key_constraint(:staff_shift_id)
  end

  def void_changeset(cash_out, attrs) do
    cash_out
    |> cast(attrs, [:status, :voided_at, :voided_by_user_id, :void_reason])
    |> validate_required([:status, :voided_at, :voided_by_user_id, :void_reason])
    |> validate_inclusion(:status, ["voided"])
    |> validate_change(:void_reason, fn :void_reason, reason ->
      if is_binary(reason) and String.trim(reason) != "" do
        []
      else
        [void_reason: "can't be blank"]
      end
    end)
    |> update_change(:void_reason, &normalize_required_text/1)
    |> foreign_key_constraint(:voided_by_user_id)
  end

  defp normalize_optional_text(nil), do: nil

  defp normalize_optional_text(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_text(_), do: nil

  defp normalize_required_text(nil), do: nil

  defp normalize_required_text(text) when is_binary(text), do: String.trim(text)
  defp normalize_required_text(_), do: nil
end
