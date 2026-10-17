defmodule Espreso.Repo.Migrations.CreatePettyCashEntries do
  use Ecto.Migration

  def change do
    create table(:petty_cash_entries) do
      add :amount, :decimal, null: false
      add :category, :string, null: false
      add :note, :string, null: false
      add :recorded_at, :utc_datetime, null: false
      add :shop_date, :date, null: false
      add :status, :string, null: false, default: "recorded"
      add :voided_at, :utc_datetime
      add :void_reason, :string

      add :created_by_user_id, references(:users, on_delete: :nothing), null: false
      add :staff_shift_id, references(:staff_shifts, on_delete: :nilify_all)
      add :voided_by_user_id, references(:users, on_delete: :nilify_all)
      add :tenant_id, references(:tenants, on_delete: :nothing), null: false
      add :branch_id, references(:branches, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:petty_cash_entries, [:branch_id, :shop_date, :status])
    create index(:petty_cash_entries, [:created_by_user_id])
    create index(:petty_cash_entries, [:staff_shift_id])
  end
end
