defmodule Espreso.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :name, :string, null: false
      add :description, :text
      add :available, :boolean, default: true, null: false
      add :category_id, references(:categories, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:products, [:category_id])
  end
end
