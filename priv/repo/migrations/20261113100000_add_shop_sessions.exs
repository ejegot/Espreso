defmodule Espreso.Repo.Migrations.AddShopSessions do
  use Ecto.Migration

  def change do
    alter table(:shop_day_opens) do
      add :session_active, :boolean
    end

    drop unique_index(:shop_day_opens, [:branch_id, :shop_date])
    create index(:shop_day_opens, [:branch_id, :shop_date])

    create unique_index(:shop_day_opens, [:branch_id],
             where: "session_active = true",
             name: :shop_day_opens_one_active_session_per_branch
           )

    alter table(:shift_closes) do
      add :shop_session_id, references(:shop_day_opens, on_delete: :restrict)
    end

    drop unique_index(:shift_closes, [:branch_id, :shop_date])
    create index(:shift_closes, [:branch_id, :shop_date])
    create unique_index(:shift_closes, [:shop_session_id])

    for table <- [:orders, :cash_outs, :petty_cash_entries] do
      alter table(table) do
        add :shop_session_id, references(:shop_day_opens, on_delete: :restrict)
      end

      create index(table, [:shop_session_id])
    end
  end
end
