defmodule Espreso.Tenancy.TenantsTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.Marketing
  alias Espreso.Menu
  alias Espreso.Repo
  alias Espreso.Tenancy
  alias Espreso.Tenancy.Tenants

  setup do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "CS Owner",
        email: "cs.owner.tenants@test.local",
        password: "password123",
        role: "owner"
      })

    %{owner: owner}
  end

  test "platform owner creates an isolated café", %{owner: owner} do
    assert Tenancy.platform_owner?(owner)

    assert {:ok, %{tenant: tenant, branch: branch, owner: cafe_owner}} =
             Tenants.create_as(owner, %{
               name: "Kape ni Juan",
               owner_name: "Juan",
               pin: "2468",
               pin_confirmation: "2468",
               address: "Quezon City"
             })

    assert tenant.slug == "kape-ni-juan"
    assert tenant.guest_brand_name == "Kape ni Juan"
    assert branch.main
    assert branch.slug == "main"
    assert cafe_owner.role == "owner"
    assert cafe_owner.tenant_id == tenant.id
    assert cafe_owner.branch_id == branch.id
    assert Tenants.guest_menu_path(tenant) == "/t/kape-ni-juan/menu"
    assert Tenants.guest_login_path(tenant) == "/t/kape-ni-juan/login"
    refute Tenancy.platform_owner?(cafe_owner)

    Tenancy.put_context(%{tenant_id: tenant.id, branch_id: branch.id})
    assert Menu.list_menu() == []
    assert Enum.any?(Accounts.list_staff_for_pin_login(), &(&1.id == cafe_owner.id))

    Tenancy.put_lilac_context()
    refute Enum.any?(Accounts.list_staff_for_pin_login(), &(&1.id == cafe_owner.id))
  end

  test "renter owner cannot add a tenant", %{owner: owner} do
    {:ok, %{owner: renter}} =
      Tenants.create_as(owner, %{
        name: "Renter Cafe",
        owner_name: "Ria",
        pin: "1357"
      })

    assert {:error, :unauthorized} =
             Tenants.create_as(renter, %{
               name: "Should Fail",
               owner_name: "X",
               pin: "1111"
             })
  end

  test "opening a waitlist request marks it opened and copies contact", %{owner: owner} do
    {:ok, request} =
      Marketing.create_shop_request(%{
        "contact_name" => "Ana",
        "cafe_name" => "Waitlist Brew",
        "city" => "Marikina",
        "email" => "ana@waitlist.ph",
        "mobile" => "09171234567"
      })

    assert {:ok, %{tenant: tenant, branch: branch}} =
             Tenants.create_as(owner, %{
               name: request.cafe_name,
               owner_name: request.contact_name,
               address: request.city,
               pin: "1357",
               shop_request_id: request.id
             })

    request = Repo.reload!(request)
    assert request.status == "opened"
    assert request.tenant_id == tenant.id

    settings = Espreso.BusinessSettings.get_for_branch(branch.id)
    assert settings.email == "ana@waitlist.ph"
    assert settings.phone == "+639171234567"
    assert settings.address == "Marikina"
  end
end
