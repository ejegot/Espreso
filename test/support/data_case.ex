defmodule Espreso.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Espreso.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Espreso.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Espreso.DataCase
    end
  end

  setup tags do
    Espreso.DataCase.setup_sandbox(tags)
    unless tags[:without_shop_open], do: ensure_shop_day_open!()
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Espreso.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Opens today's shop day so order/POS tests match production selling gates.
  """
  def ensure_shop_day_open! do
    alias Espreso.Accounts
    alias Espreso.Shifts

    if is_nil(Shifts.get_todays_open()) do
      {:ok, user} =
        Accounts.register_user(%{
          name: "Shop Open",
          email: "shop-open-#{System.unique_integer([:positive])}@test.local",
          password: "password123",
          role: "manager"
        })

      {:ok, _} = Shifts.record_open(user, %{opening_cash: "0"})
    end

    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
