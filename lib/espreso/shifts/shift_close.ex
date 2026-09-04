defmodule Espreso.Shifts.ShiftClose do
  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Accounts.User

  schema "shift_closes" do
    field :shop_date, :date
    field :system_total, :decimal
    field :system_count, :integer
    field :by_via, :map, default: %{}
    field :counted_cash, :decimal
    field :notes, :string
    field :closed_at, :utc_datetime

    belongs_to :closed_by_user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(shift_close, attrs) do
    shift_close
    |> cast(attrs, [
      :shop_date,
      :system_total,
      :system_count,
      :by_via,
      :counted_cash,
      :notes,
      :closed_by_user_id,
      :closed_at
    ])
    |> validate_required([
      :shop_date,
      :system_total,
      :system_count,
      :by_via,
      :closed_by_user_id,
      :closed_at
    ])
    |> validate_number(:system_count, greater_than_or_equal_to: 0)
    |> validate_length(:notes, max: 500)
    |> unique_constraint(:shop_date)
    |> foreign_key_constraint(:closed_by_user_id)
  end
end
