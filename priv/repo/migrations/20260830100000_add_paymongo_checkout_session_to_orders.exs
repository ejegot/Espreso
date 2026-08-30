defmodule Espreso.Repo.Migrations.AddPaymongoCheckoutSessionToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :paymongo_checkout_session_id, :string
    end

    create index(:orders, [:paymongo_checkout_session_id])
  end
end
