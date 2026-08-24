defmodule Espreso.BusinessSettings.Setting do
  @moduledoc """
  Singleton shop contact / hours / social settings.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "business_settings" do
    field :business_name, :string
    field :address, :string
    field :phone, :string
    field :email, :string
    field :hours_lines, {:array, :string}, default: []
    field :instagram_url, :string
    field :facebook_url, :string
    field :tiktok_url, :string
    field :singleton_key, :integer, default: 1
    field :hours_text, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [
    :business_name,
    :address,
    :phone,
    :email,
    :instagram_url,
    :facebook_url,
    :tiktok_url
  ]

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @required_fields ++ [:hours_lines, :hours_text])
    |> put_hours_lines_from_text()
    |> update_change(:business_name, &trim/1)
    |> update_change(:address, &trim/1)
    |> update_change(:phone, &trim/1)
    |> update_change(:email, &normalize_email/1)
    |> update_change(:instagram_url, &trim/1)
    |> update_change(:facebook_url, &trim/1)
    |> update_change(:tiktok_url, &trim/1)
    |> validate_required(@required_fields)
    |> validate_length(:business_name, min: 1, max: 120)
    |> validate_length(:address, min: 1, max: 500)
    |> validate_length(:phone, min: 5, max: 40)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_url(:instagram_url)
    |> validate_url(:facebook_url)
    |> validate_url(:tiktok_url)
    |> validate_hours_lines()
    |> unique_constraint(:singleton_key)
  end

  defp put_hours_lines_from_text(changeset) do
    params = changeset.params || %{}

    if Map.has_key?(params, "hours_text") or Map.has_key?(params, :hours_text) do
      text = get_field(changeset, :hours_text) || ""

      lines =
        text
        |> String.split(~r/\r?\n/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      put_change(changeset, :hours_lines, lines)
    else
      changeset
    end
  end

  defp validate_hours_lines(changeset) do
    lines = get_field(changeset, :hours_lines) || []

    cond do
      lines == [] ->
        add_error(changeset, :hours_text, "can't be blank")

      Enum.any?(lines, &(String.length(&1) > 200)) ->
        add_error(changeset, :hours_text, "each line must be at most 200 characters")

      true ->
        changeset
    end
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and String.starts_with?(value, ["http://", "https://"]) do
        []
      else
        [{field, "must be a valid URL"}]
      end
    end)
  end

  defp trim(nil), do: nil
  defp trim(value) when is_binary(value), do: String.trim(value)

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
  end
end
