defmodule Espreso.Tenancy.Tenant do
  @moduledoc """
  A company / brand on Elilai (CoffeeSpot, or a renter café).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "tenants" do
    field :name, :string
    field :slug, :string
    field :guest_brand_name, :string

    has_many :branches, Espreso.Tenancy.Branch

    timestamps(type: :utc_datetime)
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :slug, :guest_brand_name])
    |> update_change(:name, &trim/1)
    |> update_change(:slug, &normalize_slug/1)
    |> update_change(:guest_brand_name, &trim/1)
    |> validate_required([:name, :slug, :guest_brand_name])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:slug, min: 2, max: 40)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_length(:guest_brand_name, min: 1, max: 80)
    |> unique_constraint(:slug)
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
