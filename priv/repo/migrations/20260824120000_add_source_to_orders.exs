defmodule Espreso.Repo.Migrations.AddSourceToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :source, :string, null: false, default: "customer"
    end

    create index(:orders, [:source])
  end
end
