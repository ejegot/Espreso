defmodule Espreso.Repo.Migrations.AddItemOwnerToProductsAndOrderItems do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :item_owner, :string
    end

    alter table(:order_items) do
      add :item_owner, :string
    end
  end
end
