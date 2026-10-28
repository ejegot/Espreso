defmodule Espreso.Repo.Migrations.AddOrderDuplicateVoidAudit do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :duplicate_voided_at, :utc_datetime
      add :duplicate_voided_by_user_id, references(:users, on_delete: :nilify_all)
      add :duplicate_void_reason, :string
    end

    create index(:orders, [:duplicate_voided_by_user_id])
  end
end
