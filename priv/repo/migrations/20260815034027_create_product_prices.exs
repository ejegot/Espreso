defmodule Espreso.Repo.Migrations.CreateProductPrices do
  use Ecto.Migration

  def change do
    create table(:product_prices) do
      add :size, :string
      add :price, :decimal, null: false
      add :product_id, references(:products, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:product_prices, [:product_id])

    create constraint(:product_prices, :price_must_be_non_negative, check: "price >= 0")
  end
end
