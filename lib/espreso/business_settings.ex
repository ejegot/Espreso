defmodule Espreso.BusinessSettings do
  @moduledoc """
  Owner-managed shop contact, hours, and social links (singleton).
  """

  import Ecto.Query

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.BusinessSettings.Setting
  alias Espreso.Repo

  @defaults %{
    business_name: "CoffeeSpot",
    address: "84 Lilac St., Concepcion Dos, Marikina City, Philippines, 1811",
    phone: "+639566728906",
    email: "elilaicorp.ph@gmail.com",
    hours_lines: [
      "Mon–Thu · 8:00 AM – 12:00 AM",
      "Fri–Sun · 8:00 AM – 10:00 PM",
      "Student Hour · Mon–Thu, 2:00 PM – 5:00 PM",
      "Holiday hours on Instagram"
    ],
    instagram_url: "https://www.instagram.com/coffeespot_lilac.marikina/",
    facebook_url: "https://www.facebook.com/profile.php?id=61572602608495",
    tiktok_url: "https://www.tiktok.com/@coffeespotlilac_",
    singleton_key: 1
  }

  @doc """
  Returns the singleton settings row, creating defaults if missing.
  """
  def get do
    case Repo.one(from s in Setting, limit: 1) do
      %Setting{} = setting -> setting
      nil -> ensure_defaults!()
    end
  end

  @doc """
  Idempotent insert of the default CoffeeSpot settings row.
  """
  def ensure_defaults! do
    case Repo.one(from s in Setting, limit: 1) do
      %Setting{} = setting ->
        setting

      nil ->
        %Setting{}
        |> Setting.changeset(@defaults)
        |> Repo.insert!()
    end
  end

  def defaults, do: @defaults

  def change(%Setting{} = setting, attrs \\ %{}) do
    setting
    |> with_hours_text()
    |> Setting.changeset(attrs)
  end

  @doc """
  Updates settings when the actor has `:business_settings` permission.
  """
  def update_as(%User{} = actor, attrs) when is_map(attrs) do
    with :ok <- Authorization.authorize(actor, :business_settings) do
      get()
      |> Setting.changeset(normalize_attrs(attrs))
      |> Repo.update()
    end
  end

  defp with_hours_text(%Setting{} = setting) do
    %{setting | hours_text: Enum.join(setting.hours_lines || [], "\n")}
  end

  defp normalize_attrs(attrs) do
    # Allow form maps with string keys for hours_text.
    attrs
  end
end
