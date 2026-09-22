defmodule Espreso.Menu.ProductPhoto do
  use Ecto.Schema
  import Ecto.Changeset

  schema "product_photos" do
    field :content_type, :string
    field :data, :binary

    belongs_to :product, Espreso.Menu.Product

    timestamps(type: :utc_datetime)
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:content_type, :data, :product_id])
    |> validate_required([:content_type, :data, :product_id])
    |> validate_inclusion(:content_type, ["image/jpeg", "image/png", "image/webp"])
    |> unique_constraint(:product_id)
    |> foreign_key_constraint(:product_id)
  end
end
