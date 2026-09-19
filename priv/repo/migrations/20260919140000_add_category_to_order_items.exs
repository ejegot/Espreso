defmodule Espreso.Repo.Migrations.AddCategoryToOrderItems do
  use Ecto.Migration

  def change do
    alter table(:order_items) do
      add :category, :string
    end
  end
end
