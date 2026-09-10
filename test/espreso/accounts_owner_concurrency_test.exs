defmodule Espreso.AccountsOwnerConcurrencyTest do
  use Espreso.DataCase, async: false

  alias Espreso.Accounts

  test "mutual owner disable leaves exactly one active Owner" do
    {:ok, owner_a} =
      Accounts.register_user(%{
        name: "Conc Owner A",
        email: "conc.owner.a@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    {:ok, owner_b} =
      Accounts.register_user(%{
        name: "Conc Owner B",
        email: "conc.owner.b@coffeespot.local",
        password: "password123",
        role: "owner"
      })

    parent = self()

    task_a =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
        Accounts.update_user_as(owner_a, owner_b, %{active: false})
      end)

    task_b =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())
        Accounts.update_user_as(owner_b, owner_a, %{active: false})
      end)

    results = [Task.await(task_a, 5_000), Task.await(task_b, 5_000)]

    assert Enum.any?(results, &match?({:ok, _}, &1))
    assert Enum.any?(results, &(&1 == {:error, :last_owner}))

    active_owners =
      Accounts.list_users()
      |> Enum.filter(&(&1.role == "owner" and &1.active))

    assert length(active_owners) == 1
  end
end
