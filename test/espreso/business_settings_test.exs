defmodule Espreso.BusinessSettingsTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.BusinessSettings
  alias Espreso.BusinessSettings.Setting

  test "get returns the singleton settings row" do
    settings = BusinessSettings.get()
    assert %Setting{} = settings
    assert settings.id == BusinessSettings.get().id
  end

  test "seeded defaults match current CoffeeSpot values" do
    settings = BusinessSettings.get()
    defaults = BusinessSettings.defaults()

    assert settings.business_name == defaults.business_name
    assert settings.address == defaults.address
    assert settings.phone == defaults.phone
    assert settings.email == defaults.email
    assert settings.hours_lines == defaults.hours_lines
    assert settings.instagram_url == defaults.instagram_url
    assert settings.facebook_url == defaults.facebook_url
    assert settings.tiktok_url == defaults.tiktok_url
  end

  test "ensure_defaults! is idempotent" do
    first = BusinessSettings.ensure_defaults!()
    second = BusinessSettings.ensure_defaults!()
    assert first.id == second.id
    assert Repo.aggregate(Setting, :count, :id) == 1
  end

  test "owner can update settings" do
    owner = register!("Owner", "owner.settings@test.local", "owner")

    assert {:ok, updated} =
             BusinessSettings.update_as(owner, %{
               "business_name" => "CoffeeSpot Lilac",
               "address" => "84 Lilac St., Concepcion Dos, Marikina City, Philippines, 1811",
               "phone" => "+639566728906",
               "email" => "hello@coffeespot.local",
               "hours_text" => "Daily · 8:00 AM – 10:00 PM",
               "instagram_url" => "https://www.instagram.com/coffeespot_lilac.marikina/",
               "facebook_url" => "https://www.facebook.com/profile.php?id=61572602608495",
               "tiktok_url" => "https://www.tiktok.com/@coffeespotlilac_"
             })

    assert updated.business_name == "CoffeeSpot Lilac"
    assert updated.email == "hello@coffeespot.local"
    assert updated.hours_lines == ["Daily · 8:00 AM – 10:00 PM"]
  end

  test "invalid values fail validation" do
    owner = register!("Owner", "owner.invalid@test.local", "owner")

    assert {:error, changeset} =
             BusinessSettings.update_as(owner, %{
               "business_name" => "",
               "address" => "",
               "phone" => "",
               "email" => "not-an-email",
               "hours_text" => "",
               "instagram_url" => "not-a-url",
               "facebook_url" => "https://www.facebook.com/profile.php?id=61572602608495",
               "tiktok_url" => "https://www.tiktok.com/@coffeespotlilac_"
             })

    errors = errors_on(changeset)
    assert errors.business_name
    assert errors.address
    assert errors.phone
    assert errors.email
    assert errors.hours_text
    assert errors.instagram_url
  end

  test "manager and staff cannot update settings" do
    manager = register!("Manager", "manager.settings@test.local", "manager")
    staff = register!("Staff", "staff.settings@test.local", "barista")

    attrs = %{
      "business_name" => "Nope",
      "address" => "Somewhere",
      "phone" => "+639566728906",
      "email" => "nope@coffeespot.local",
      "hours_text" => "Closed",
      "instagram_url" => "https://www.instagram.com/coffeespot_lilac.marikina/",
      "facebook_url" => "https://www.facebook.com/profile.php?id=61572602608495",
      "tiktok_url" => "https://www.tiktok.com/@coffeespotlilac_"
    }

    assert {:error, :unauthorized} = BusinessSettings.update_as(manager, attrs)
    assert {:error, :unauthorized} = BusinessSettings.update_as(staff, attrs)
    assert BusinessSettings.get().business_name == BusinessSettings.defaults().business_name
  end

  defp register!(name, email, role) do
    {:ok, user} =
      Accounts.register_user(%{
        name: name,
        email: email,
        password: "password123",
        role: role
      })

    user
  end
end
