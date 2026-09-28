defmodule Espreso.Marketing.ShopRequest do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Espreso.Customers

  schema "shop_requests" do
    field :contact_name, :string
    field :cafe_name, :string
    field :city, :string
    field :email, :string
    field :phone_e164, :string
    field :note, :string
    field :status, :string, default: "pending"
    field :mobile, :string, virtual: true
    field :company_url, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [:contact_name, :cafe_name, :city, :email, :mobile, :note, :company_url])
    |> update_change(:contact_name, &trim/1)
    |> update_change(:cafe_name, &trim/1)
    |> update_change(:city, &trim/1)
    |> update_change(:email, &normalize_email/1)
    |> update_change(:mobile, &trim/1)
    |> update_change(:note, &blank_to_nil/1)
    |> validate_required([:contact_name, :cafe_name, :city, :email, :mobile])
    |> validate_length(:contact_name, min: 2, max: 80)
    |> validate_length(:cafe_name, min: 2, max: 80)
    |> validate_length(:city, min: 2, max: 80)
    |> validate_length(:note, max: 1000)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
    |> put_phone_e164()
  end

  defp put_phone_e164(changeset) do
    mobile = get_change(changeset, :mobile) || get_field(changeset, :mobile)

    cond do
      is_nil(mobile) or mobile == "" ->
        changeset

      true ->
        case Customers.normalize_phone(mobile) do
          {:ok, phone} -> put_change(changeset, :phone_e164, phone)
          {:error, :invalid_phone} -> add_error(changeset, :mobile, "must be a Philippine mobile")
        end
    end
  end

  defp trim(nil), do: nil
  defp trim(value) when is_binary(value), do: String.trim(value)

  defp normalize_email(nil), do: nil

  defp normalize_email(value) when is_binary(value) do
    value |> String.trim() |> String.downcase()
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
