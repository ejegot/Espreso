defmodule Espreso.Menu.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :name, :string
    field :description, :string
    field :available, :boolean, default: true

    belongs_to :category, Espreso.Menu.Category
    has_many :product_prices, Espreso.Menu.ProductPrice

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :description, :available, :category_id])
    |> validate_required([:name, :available, :category_id])
    |> foreign_key_constraint(:category_id)
  end
end
