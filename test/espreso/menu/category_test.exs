defmodule Espreso.Menu.CategoryTest do
  use Espreso.DataCase, async: true

  alias Espreso.Menu.Category
  alias Espreso.Repo

  describe "changeset/2" do
    test "is valid with a name" do
      changeset = Category.changeset(%Category{}, %{name: "HOT"})

      assert changeset.valid?
    end

    test "requires a name" do
      changeset = Category.changeset(%Category{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires name to be unique" do
      {:ok, _category} =
        %Category{}
        |> Category.changeset(%{name: "HOT"})
        |> Repo.insert()

      {:error, changeset} =
        %Category{}
        |> Category.changeset(%{name: "HOT"})
        |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).name
    end
  end
end
