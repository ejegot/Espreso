defmodule Espreso.Repo.Migrations.CreateShiftCloses do
  use Ecto.Migration

  def change do
    create table(:shift_closes) do
      add :shop_date, :date, null: false
      add :system_total, :decimal, null: false
      add :system_count, :integer, null: false
      add :by_via, :map, null: false, default: %{}
      add :counted_cash, :decimal
      add :notes, :string
      add :closed_by_user_id, references(:users, on_delete: :nilify_all)
      add :closed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shift_closes, [:shop_date])
    create index(:shift_closes, [:closed_by_user_id])
  end
end
