defmodule Espreso.Shifts.ShopDayOpen do
  @moduledoc """
  Opening cash and state for one shop session.

  Separate from barista Time In (`StaffShift`) and from `ShiftClose`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Accounts.User

  schema "shop_day_opens" do
    field :shop_date, :date
    field :opening_cash, :decimal
    field :opened_at, :utc_datetime
    field :notes, :string
    field :session_active, :boolean

    belongs_to :opened_by_user, User
    belongs_to :tenant, Espreso.Tenancy.Tenant
    belongs_to :branch, Espreso.Tenancy.Branch

    timestamps(type: :utc_datetime)
  end

  def changeset(open, attrs) do
    open
    |> cast(attrs, [
      :shop_date,
      :opening_cash,
      :opened_at,
      :opened_by_user_id,
      :notes,
      :session_active,
      :tenant_id,
      :branch_id
    ])
    |> validate_required([:shop_date, :opening_cash, :opened_at, :opened_by_user_id])
    |> validate_number(:opening_cash, greater_than_or_equal_to: 0)
    |> validate_length(:notes, max: 500)
    |> Espreso.Tenancy.put_ids()
    |> unique_constraint(:session_active, name: :shop_day_opens_one_active_session_per_branch)
    |> foreign_key_constraint(:opened_by_user_id)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:branch_id)
  end
end
