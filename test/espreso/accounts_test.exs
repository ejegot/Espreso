defmodule Espreso.AccountsTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User

  test "register and authenticate user" do
    assert {:ok, user} =
             Accounts.register_user(%{
               name: "Ana",
               email: "ana@coffeespot.local",
               password: "password123",
               role: "barista"
             })

    assert user.email == "ana@coffeespot.local"
    assert user.role == "barista"
    assert user.password_hash
    refute Map.get(user, :password)

    assert {:ok, authed} = Accounts.authenticate_user("Ana@CoffeeSpot.local", "password123")
    assert authed.id == user.id

    assert {:error, :invalid_credentials} =
             Accounts.authenticate_user("ana@coffeespot.local", "wrong")
  end

  test "inactive user cannot authenticate" do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Ben",
        email: "ben@coffeespot.local",
        password: "password123",
        role: "barista"
      })

    {:ok, _} = Accounts.update_user(user, %{active: false})

    assert {:error, :invalid_credentials} =
             Accounts.authenticate_user("ben@coffeespot.local", "password123")
  end

  test "first self-registered user becomes owner" do
    assert Accounts.first_user?()

    assert {:ok, owner} =
             Accounts.register_self(%{
               "name" => "First",
               "email" => "first@coffeespot.local",
               "password" => "password123",
               "role" => "barista"
             })

    assert owner.role == "owner"
    refute Accounts.first_user?()
  end

  test "public registration cannot create owner when users exist" do
    {:ok, _} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    assert {:ok, user} =
             Accounts.register_self(%{
               "name" => "Hacker",
               "email" => "hacker@coffeespot.local",
               "password" => "password123",
               "role" => "owner"
             })

    assert user.role == "barista"
  end

  test "public registration may choose staff or manager" do
    {:ok, _} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner2@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    assert {:ok, staff} =
             Accounts.register_self(%{
               "name" => "Staff",
               "email" => "staff@coffeespot.local",
               "password" => "password123",
               "role" => "barista"
             })

    assert staff.role == "barista"

    assert {:ok, manager} =
             Accounts.register_self(%{
               "name" => "Mgr",
               "email" => "mgr@coffeespot.local",
               "password" => "password123",
               "role" => "manager"
             })

    assert manager.role == "manager"
  end

  test "role permission matrix" do
    staff = %User{role: "barista", active: true}
    manager = %User{role: "manager", active: true}
    owner = %User{role: "owner", active: true}
    inactive = %User{role: "owner", active: false}

    for permission <- [:dashboard, :view_menu, :orders] do
      assert Authorization.can?(staff, permission)
      assert Authorization.can?(manager, permission)
      assert Authorization.can?(owner, permission)
    end

    for permission <- [:edit_menu, :product_availability, :reports] do
      refute Authorization.can?(staff, permission)
      assert Authorization.can?(manager, permission)
      assert Authorization.can?(owner, permission)
    end

    for permission <- [:user_management, :business_settings] do
      refute Authorization.can?(staff, permission)
      refute Authorization.can?(manager, permission)
      assert Authorization.can?(owner, permission)
    end

    refute Authorization.can?(inactive, :orders)
    refute Authorization.can?(inactive, :user_management)

    assert User.can_access_orders?(staff)
    assert User.can_manage_users?(owner)
    refute User.can_manage_users?(manager)
    refute User.can_manage_users?(staff)
  end

  test "non-owners cannot create or update users via authorized APIs" do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner3@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    {:ok, staff} =
      Accounts.register_user(%{
        name: "Staff",
        email: "staff3@coffeespot.local",
        password: "password123",
        role: "barista"
      })

    {:ok, manager} =
      Accounts.register_user(%{
        name: "Manager",
        email: "manager3@coffeespot.local",
        password: "password123",
        role: "manager"
      })

    assert {:error, :unauthorized} =
             Accounts.create_user_as(staff, %{
               "name" => "X",
               "email" => "x@coffeespot.local",
               "password" => "password123",
               "role" => "owner"
             })

    assert {:error, :unauthorized} =
             Accounts.create_user_as(manager, %{
               "name" => "Y",
               "email" => "y@coffeespot.local",
               "password" => "password123",
               "role" => "barista"
             })

    assert {:error, :unauthorized} =
             Accounts.update_user_as(staff, owner, %{"role" => "barista"})

    assert {:error, :unauthorized} =
             Accounts.update_user_as(manager, staff, %{"role" => "owner"})
  end

  test "users cannot escalate their own role" do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner",
        email: "owner4@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    {:ok, staff} =
      Accounts.register_user(%{
        name: "Staff",
        email: "staff4@coffeespot.local",
        password: "password123",
        role: "barista"
      })

    assert {:ok, still_owner} =
             Accounts.update_user_as(owner, owner, %{
               "name" => "Owner Updated",
               "email" => owner.email,
               "role" => "barista"
             })

    assert still_owner.role == "owner"
    assert still_owner.name == "Owner Updated"

    assert {:ok, promoted} =
             Accounts.update_user_as(owner, staff, %{
               "name" => staff.name,
               "email" => staff.email,
               "role" => "manager"
             })

    assert promoted.role == "manager"
  end

  test "owner cannot deactivate self through update_user_as" do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Solo Owner",
        email: "solo.owner@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    assert {:error, :cannot_deactivate_self} =
             Accounts.update_user_as(owner, owner, %{active: false})

    assert Accounts.get_user!(owner.id).active
  end

  test "cannot disable or demote an Owner when they are the last active Owner" do
    {:ok, owner_a} =
      Accounts.register_user(%{
        name: "Owner A",
        email: "owner.a.last@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    {:ok, owner_b} =
      Accounts.register_user(%{
        name: "Owner B",
        email: "owner.b.last@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    assert {:ok, _} = Accounts.update_user_as(owner_a, owner_b, %{active: false})

    assert {:error, :cannot_deactivate_self} =
             Accounts.update_user_as(owner_a, owner_a, %{active: false})

    # Inactive Owners must not count: add one and keep owner_a as sole active Owner.
    {:ok, inactive_owner} =
      Accounts.register_user(%{
        name: "Parked Owner",
        email: "parked.owner.last@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    {:ok, _} = Accounts.update_user(inactive_owner, %{active: false})

    assert {:error, :cannot_deactivate_self} =
             Accounts.update_user_as(owner_a, owner_a, %{active: false})

    assert {:ok, still} =
             Accounts.update_user_as(owner_a, owner_a, %{
               "name" => "Owner A Renamed",
               "email" => owner_a.email,
               "role" => "manager"
             })

    assert still.role == "owner"
    assert still.name == "Owner A Renamed"
    assert still.active

    # Stale in-memory Owner actor (demoted in DB) must still be blocked by last-owner.
    {:ok, owner_b} =
      Accounts.update_user_as(owner_a, Accounts.get_user!(owner_b.id), %{
        "name" => owner_b.name,
        "email" => owner_b.email,
        "role" => "owner",
        "active" => true
      })

    stale_b = owner_b

    assert {:ok, _} =
             Accounts.update_user_as(owner_a, owner_b, %{
               "name" => owner_b.name,
               "email" => owner_b.email,
               "role" => "manager"
             })

    assert {:error, :last_owner} =
             Accounts.update_user_as(stale_b, owner_a, %{active: false})

    assert {:error, :last_owner} =
             Accounts.update_user_as(stale_b, owner_a, %{
               "name" => owner_a.name,
               "email" => owner_a.email,
               "role" => "barista"
             })

    assert Accounts.get_user!(owner_a.id).active
    assert Accounts.get_user!(owner_a.id).role == "owner"
  end

  test "inactive Owners do not count toward last-owner protection" do
    {:ok, owner_a} =
      Accounts.register_user(%{
        name: "Active Owner",
        email: "active.owner.safety@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    {:ok, inactive} =
      Accounts.register_user(%{
        name: "Inactive Owner",
        email: "inactive.owner.safety@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    {:ok, _} = Accounts.update_user(inactive, %{active: false})

    {:ok, owner_b} =
      Accounts.register_user(%{
        name: "Actor Owner",
        email: "actor.owner.safety@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    assert {:ok, _} = Accounts.update_user_as(owner_b, owner_a, %{active: false})

    inactive = Accounts.get_user!(inactive.id)
    owner_a = Accounts.get_user!(owner_a.id)

    # Reloaded inactive Owner cannot authorize user management.
    assert {:error, :unauthorized} =
             Accounts.update_user_as(inactive, owner_b, %{
               "name" => owner_b.name,
               "email" => owner_b.email,
               "role" => "manager"
             })

    assert {:error, :unauthorized} =
             Accounts.update_user_as(owner_a, owner_b, %{active: false})

    assert {:error, :cannot_deactivate_self} =
             Accounts.update_user_as(owner_b, owner_b, %{active: false})

    assert Accounts.get_user!(owner_b.id).active
    assert Accounts.get_user!(owner_b.id).role == "owner"
  end

  test "can disable or demote an Owner when another active Owner remains" do
    {:ok, owner_a} =
      Accounts.register_user(%{
        name: "Owner A2",
        email: "owner.a2.safety@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    {:ok, owner_b} =
      Accounts.register_user(%{
        name: "Owner B2",
        email: "owner.b2.safety@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    assert {:ok, disabled} = Accounts.update_user_as(owner_a, owner_b, %{active: false})
    refute disabled.active

    {:ok, owner_c} =
      Accounts.register_user(%{
        name: "Owner C2",
        email: "owner.c2.safety@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    assert {:ok, demoted} =
             Accounts.update_user_as(owner_a, owner_c, %{
               "name" => owner_c.name,
               "email" => owner_c.email,
               "role" => "manager"
             })

    assert demoted.role == "manager"
  end

  test "can edit last Owner non-role fields and create additional Owners" do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Editable Owner",
        email: "editable.owner@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    assert {:ok, updated} =
             Accounts.update_user_as(owner, owner, %{
               "name" => "Editable Owner Updated",
               "email" => "editable.owner@coffeespot.local"
             })

    assert updated.name == "Editable Owner Updated"
    assert updated.role == "owner"
    assert updated.active

    assert {:ok, second} =
             Accounts.create_user_as(owner, %{
               "name" => "Second Owner",
               "email" => "second.owner.safety@coffeespot.local",
               "password" => "password123",
               "role" => "owner"
             })

    assert second.role == "owner"
  end

  test "set_pin, verify_pin, and clear_pin" do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Pin User",
        email: "pin@coffeespot.local",
        password: "password123",
        role: "barista"
      })

    refute Accounts.pin_set?(user)

    assert {:ok, with_pin} = Accounts.set_pin(user, "1234")
    assert Accounts.pin_set?(with_pin)
    assert {:ok, verified} = Accounts.verify_pin(with_pin, "1234")
    assert verified.id == user.id
    assert {:ok, verified_again} = Accounts.verify_pin(to_string(user.id), "1234")
    assert verified_again.id == user.id

    assert {:error, :invalid_pin} = Accounts.verify_pin(with_pin, "9999")
    assert {:error, :invalid_pin_format} = Accounts.set_pin(with_pin, "12")
    assert {:error, :invalid_pin_format} = Accounts.set_pin(with_pin, "1234567")

    assert {:ok, cleared} = Accounts.clear_pin(with_pin)
    refute Accounts.pin_set?(cleared)
    assert {:error, :pin_not_set} = Accounts.verify_pin(cleared, "1234")
  end

  test "inactive user cannot verify pin" do
    {:ok, user} =
      Accounts.register_user(%{
        name: "Inactive Pin",
        email: "inactive.pin@coffeespot.local",
        password: "password123",
        role: "barista"
      })

    {:ok, user} = Accounts.set_pin(user, "4321")
    {:ok, _} = Accounts.update_user(user, %{active: false})

    assert {:error, :inactive} = Accounts.verify_pin(user, "4321")
  end

  test "owner can set pin for staff via set_pin_as" do
    {:ok, owner} =
      Accounts.register_user(%{
        name: "Owner Pin",
        email: "owner.pin@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    {:ok, staff} =
      Accounts.register_user(%{
        name: "Staff Pin",
        email: "staff.pin@coffeespot.local",
        password: "password123",
        role: "barista"
      })

    assert {:ok, staff} = Accounts.set_pin_as(owner, staff, "5678")
    assert {:ok, _} = Accounts.verify_pin(staff, "5678")

    assert {:error, :unauthorized} = Accounts.set_pin_as(staff, owner, "1111")
  end

  test "list_active_staff_for_roster excludes inactive users" do
    {:ok, active} =
      Accounts.register_user(%{
        name: "Zara",
        email: "zara@coffeespot.local",
        password: "password123",
        role: "barista"
      })

    {:ok, inactive} =
      Accounts.register_user(%{
        name: "Inactive",
        email: "inactive.roster@coffeespot.local",
        password: "password123",
        role: "barista"
      })

    {:ok, _} = Accounts.update_user(inactive, %{active: false})

    roster = Accounts.list_active_staff_for_roster()
    ids = Enum.map(roster, & &1.id)

    assert active.id in ids
    refute inactive.id in ids
    assert Enum.all?(roster, &match?(%{id: _, name: _, role: _}, &1))
    refute Enum.any?(roster, &Map.has_key?(&1, :pin_hash))
  end
end
