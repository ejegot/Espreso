defmodule Espreso.Repo.Migrations.AddOrderRefunds do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :refunded_at, :utc_datetime
      add :refunded_by_user_id, references(:users, on_delete: :nilify_all)
      add :refund_reason, :string
    end

    create index(:orders, [:refunded_by_user_id])
  end
end
