defmodule Espreso.Tenancy.Branch do
  @moduledoc """
  One physical shop under a tenant (Lilac, or a renter's main site).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "branches" do
    field :name, :string
    field :slug, :string
    field :code, :string
    field :address, :string
    field :main, :boolean, default: false

    belongs_to :tenant, Espreso.Tenancy.Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(branch, attrs) do
    branch
    |> cast(attrs, [:name, :slug, :code, :address, :main, :tenant_id])
    |> update_change(:name, &trim/1)
    |> update_change(:slug, &normalize_slug/1)
    |> update_change(:code, &normalize_slug/1)
    |> update_change(:address, &trim/1)
    |> validate_required([:name, :slug, :code, :tenant_id])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:slug, min: 2, max: 40)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_length(:code, min: 2, max: 20)
    |> unique_constraint([:tenant_id, :slug])
    |> unique_constraint(:code)
    |> foreign_key_constraint(:tenant_id)
  end

  defp trim(nil), do: nil
  defp trim(value) when is_binary(value), do: String.trim(value)

  defp normalize_slug(nil), do: nil

  defp normalize_slug(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end
end
