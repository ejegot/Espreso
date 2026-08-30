defmodule Espreso.Repo.Migrations.UniquePaymongoCheckoutSessionOnOrders do
  use Ecto.Migration

  def change do
    drop index(:orders, [:paymongo_checkout_session_id])

    create unique_index(:orders, [:paymongo_checkout_session_id])
  end
end
