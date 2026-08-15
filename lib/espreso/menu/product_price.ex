defmodule Espreso.Menu.ProductPrice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "product_prices" do
    field :size, :string
    field :price, :decimal

    belongs_to :product, Espreso.Menu.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product_price, attrs) do
    product_price
    |> cast(attrs, [:size, :price, :product_id])
    |> validate_required([:price, :product_id])
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:product_id)
    |> check_constraint(:price, name: :price_must_be_non_negative)
  end
end
