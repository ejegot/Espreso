defmodule Espreso.Menu.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :name, :string
    field :description, :string
    field :available, :boolean, default: true
    field :menu_group, :string
    field :has_custom_photo, :boolean, default: false
    field :photo_updated_at, :utc_datetime

    belongs_to :category, Espreso.Menu.Category
    has_many :product_prices, Espreso.Menu.ProductPrice

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :name,
      :description,
      :available,
      :category_id,
      :menu_group,
      :has_custom_photo,
      :photo_updated_at
    ])
    |> update_change(:name, &trim_name/1)
    |> update_change(:menu_group, &blank_to_nil/1)
    |> validate_required([:name, :available, :category_id])
    |> validate_length(:name, min: 1, max: 80)
    |> unique_constraint(:name, name: :products_category_id_name_index)
    |> foreign_key_constraint(:category_id)
  end

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
