defmodule Espreso.Repo.Migrations.AddOnlineWalletToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :online_wallet, :string
    end
  end
end
