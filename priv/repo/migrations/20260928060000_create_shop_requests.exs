defmodule Espreso.Repo.Migrations.CreateShopRequests do
  use Ecto.Migration

  def change do
    create table(:shop_requests) do
      add :contact_name, :string, null: false
      add :cafe_name, :string, null: false
      add :city, :string, null: false
      add :email, :string, null: false
      add :phone_e164, :string, null: false
      add :note, :text
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:shop_requests, [:status])
    create index(:shop_requests, [:inserted_at])
  end
end
