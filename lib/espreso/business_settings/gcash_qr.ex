defmodule Espreso.BusinessSettings.GcashQr do
  use Ecto.Schema
  import Ecto.Changeset

  schema "business_gcash_qrs" do
    field :content_type, :string
    field :data, :binary

    belongs_to :branch, Espreso.Tenancy.Branch

    timestamps(type: :utc_datetime)
  end

  def changeset(qr, attrs) do
    qr
    |> cast(attrs, [:branch_id, :content_type, :data])
    |> validate_required([:branch_id, :content_type, :data])
    |> validate_inclusion(:content_type, ["image/jpeg", "image/png", "image/webp"])
    |> unique_constraint(:branch_id)
    |> foreign_key_constraint(:branch_id)
  end
end
