defmodule Espreso.Repo.Migrations.CreateCashOuts do
  use Ecto.Migration

  def change do
    create table(:cash_outs) do
      add :amount, :decimal, null: false
      add :category, :string, null: false
      add :note, :string
      add :recorded_at, :utc_datetime, null: false
      add :shop_date, :date, null: false
      add :status, :string, null: false, default: "recorded"
      add :voided_at, :utc_datetime
      add :void_reason, :string

      add :created_by_user_id, references(:users, on_delete: :nothing), null: false
      add :staff_shift_id, references(:staff_shifts, on_delete: :nilify_all)
      add :voided_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:cash_outs, [:shop_date])
    create index(:cash_outs, [:created_by_user_id])
    create index(:cash_outs, [:staff_shift_id])
    create index(:cash_outs, [:shop_date, :status])
  end
end
