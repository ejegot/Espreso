defmodule Espreso.AccountsBootstrapConcurrencyTest do
  use Espreso.DataCase, async: false

  alias Espreso.Accounts

  test "concurrent initial owner setup creates exactly one owner" do
    assert Accounts.first_user?()

    parent = self()

    task_a =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())

        Accounts.bootstrap_initial_owner(%{
          name: "Owner A",
          pin: "1111",
          pin_confirmation: "1111"
        })
      end)

    task_b =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Espreso.Repo, parent, self())

        Accounts.bootstrap_initial_owner(%{
          name: "Owner B",
          pin: "2222",
          pin_confirmation: "2222"
        })
      end)

    results = [Task.await(task_a, 15_000), Task.await(task_b, 15_000)]

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :registration_closed})) == 1

    owners =
      Accounts.list_users()
      |> Enum.filter(&(&1.role == "owner"))

    assert length(owners) == 1
    assert length(Accounts.list_users()) == 1
  end
end
