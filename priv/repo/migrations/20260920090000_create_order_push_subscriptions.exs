defmodule Espreso.Repo.Migrations.CreateOrderPushSubscriptions do
  use Ecto.Migration

  def change do
    create table(:order_push_subscriptions) do
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh, :string, null: false
      add :auth, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:order_push_subscriptions, [:order_id])
    create unique_index(:order_push_subscriptions, [:order_id, :endpoint])
  end
end
