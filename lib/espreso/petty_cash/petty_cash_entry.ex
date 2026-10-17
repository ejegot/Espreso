defmodule Espreso.PettyCash.PettyCashEntry do
  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Accounts.User
  alias Espreso.StaffShifts.StaffShift

  @categories ~w(Ingredients Supplies Cleaning Other)
  @statuses ~w(recorded voided)

  schema "petty_cash_entries" do
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
    belongs_to :tenant, Espreso.Tenancy.Tenant
    belongs_to :branch, Espreso.Tenancy.Branch

    timestamps(type: :utc_datetime)
  end

  def categories, do: @categories

  def create_changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :amount,
      :category,
      :note,
      :recorded_at,
      :shop_date,
      :status,
      :created_by_user_id,
      :staff_shift_id,
      :tenant_id,
      :branch_id
    ])
    |> validate_required([
      :amount,
      :category,
      :note,
      :recorded_at,
      :shop_date,
      :status,
      :created_by_user_id
    ])
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:note, max: 500)
    |> update_change(:note, &String.trim/1)
    |> validate_change(:note, fn :note, note ->
      if String.trim(note) == "", do: [note: "can't be blank"], else: []
    end)
    |> Espreso.Tenancy.put_ids()
    |> foreign_key_constraint(:created_by_user_id)
    |> foreign_key_constraint(:staff_shift_id)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:branch_id)
  end

  def void_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:status, :voided_at, :voided_by_user_id, :void_reason])
    |> validate_required([:status, :voided_at, :voided_by_user_id, :void_reason])
    |> validate_inclusion(:status, ["voided"])
    |> validate_length(:void_reason, max: 500)
    |> update_change(:void_reason, &String.trim/1)
    |> validate_change(:void_reason, fn :void_reason, reason ->
      if String.trim(reason) == "", do: [void_reason: "can't be blank"], else: []
    end)
    |> foreign_key_constraint(:voided_by_user_id)
  end
end
