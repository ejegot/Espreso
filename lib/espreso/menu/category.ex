defmodule Espreso.Menu.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string

    has_many :products, Espreso.Menu.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name])
    |> update_change(:name, &trim_name/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 30)
    |> unique_constraint(:name)
  end

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name
end
