defmodule Espreso.AccountsTest do
  use Espreso.DataCase, async: true

  alias Espreso.Accounts
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

  test "permissions" do
    barista = %User{role: "barista", active: true}
    owner = %User{role: "owner", active: true}
    inactive = %User{role: "owner", active: false}

    assert User.can_access_orders?(barista)
    assert User.can_access_orders?(owner)
    refute User.can_access_orders?(inactive)
    refute User.can_manage_users?(barista)
    assert User.can_manage_users?(owner)
  end
end
