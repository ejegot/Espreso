defmodule Espreso.Menu.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string

    belongs_to :tenant, Espreso.Tenancy.Tenant
    belongs_to :branch, Espreso.Tenancy.Branch
    has_many :products, Espreso.Menu.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :tenant_id, :branch_id])
    |> update_change(:name, &trim_name/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 30)
    |> unique_constraint(:name)
    |> Espreso.Tenancy.put_ids()
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:branch_id)
  end

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name
end
