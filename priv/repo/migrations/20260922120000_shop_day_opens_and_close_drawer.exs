defmodule Espreso.Repo.Migrations.ShopDayOpensAndCloseDrawer do
  use Ecto.Migration

  def change do
    create table(:shop_day_opens) do
      add :shop_date, :date, null: false
      add :opening_cash, :decimal, null: false
      add :opened_at, :utc_datetime, null: false
      add :opened_by_user_id, references(:users, on_delete: :nilify_all)
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shop_day_opens, [:shop_date])
    create index(:shop_day_opens, [:opened_by_user_id])

    alter table(:shift_closes) do
      add :opening_cash, :decimal
      add :expected_cash, :decimal
      add :variance, :decimal
    end
  end
end
