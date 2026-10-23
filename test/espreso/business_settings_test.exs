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

  test "owner can update payment settings" do
    owner = register!("Owner", "owner.payments@test.local", "owner")

    assert {:ok, updated} =
             BusinessSettings.update_as(owner, payment_attrs(%{"payments_mode" => "qrph_manual"}))

    assert updated.payments_mode == "qrph_manual"
    assert updated.gcash_qrph_path == "/images/gcash-qrph.png"
    assert updated.maya_qrph_path == "/images/maya-qrph.png"
    assert BusinessSettings.qrph_manual?()
    assert BusinessSettings.payment_config().payments_mode == "qrph_manual"
  end

  test "invalid payments_mode fails validation" do
    owner = register!("Owner", "owner.payments.invalid@test.local", "owner")

    assert {:error, changeset} =
             BusinessSettings.update_as(owner, payment_attrs(%{"payments_mode" => "bitcoin"}))

    assert errors_on(changeset).payments_mode
  end

  test "only owners can upload a GCash QR image" do
    manager = register!("Manager", "manager.gcash@test.local", "manager")
    staff = register!("Staff", "staff.gcash@test.local", "barista")

    png =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )

    assert {:error, :unauthorized} = BusinessSettings.save_gcash_qr_as(manager, png, "image/png")
    assert {:error, :unauthorized} = BusinessSettings.save_gcash_qr_as(staff, png, "image/png")
  end

  test "GCash QR images are isolated by branch" do
    owner = register!("Owner", "owner.gcash.branch@test.local", "owner")

    png =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )

    original_ids = Espreso.Tenancy.coffeespot_lilac_ids()

    assert {:ok, _} = BusinessSettings.save_gcash_qr_as(owner, png, "image/png")
    original_qr = BusinessSettings.get_gcash_qr()

    {:ok, branch} =
      Espreso.Tenancy.Branches.create_as(owner, %{name: "GCash QR Test Branch"})

    Espreso.Tenancy.put_context(%{tenant_id: branch.tenant_id, branch_id: branch.id})
    assert BusinessSettings.get_gcash_qr() == nil
    assert {:ok, _} = BusinessSettings.save_gcash_qr_as(owner, png <> "branch", "image/png")
    assert BusinessSettings.get_gcash_qr().branch_id == branch.id

    Espreso.Tenancy.put_context(original_ids)
    assert BusinessSettings.get_gcash_qr().id == original_qr.id
  end

  test "rejects invalid GCash QR image data" do
    owner = register!("Owner", "owner.gcash.invalid@test.local", "owner")

    assert {:error, :invalid_photo} =
             BusinessSettings.save_gcash_qr_as(owner, "not an image", "image/png")

    assert {:error, :invalid_photo} =
             BusinessSettings.save_gcash_qr_as(owner, String.duplicate("x", 40), "image/gif")
  end

  defp payment_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "business_name" => "CoffeeSpot Lilac",
        "address" => "84 Lilac St., Concepcion Dos, Marikina City, Philippines, 1811",
        "phone" => "+639566728906",
        "email" => "hello@coffeespot.local",
        "hours_text" => "Daily · 8:00 AM – 10:00 PM",
        "instagram_url" => "https://www.instagram.com/coffeespot_lilac.marikina/",
        "facebook_url" => "https://www.facebook.com/profile.php?id=61572602608495",
        "tiktok_url" => "https://www.tiktok.com/@coffeespotlilac_",
        "gcash_qrph_path" => "/images/gcash-qrph.png",
        "maya_qrph_path" => "/images/maya-qrph.png"
      },
      overrides
    )
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
