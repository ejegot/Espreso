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
