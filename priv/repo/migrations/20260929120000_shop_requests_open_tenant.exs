defmodule Espreso.Repo.Migrations.ShopRequestsOpenTenant do
  use Ecto.Migration

  def change do
    alter table(:shop_requests) do
      add :tenant_id, references(:tenants, on_delete: :nilify_all)
      add :opened_at, :utc_datetime
    end

    create index(:shop_requests, [:tenant_id])
  end
end
