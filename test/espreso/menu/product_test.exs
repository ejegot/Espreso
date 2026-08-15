defmodule Espreso.Menu.ProductTest do
  use Espreso.DataCase, async: true

  alias Espreso.Menu.{Category, Product}
  alias Espreso.Repo

  describe "changeset/2" do
    setup do
      {:ok, category} =
        %Category{}
        |> Category.changeset(%{name: "HOT"})
        |> Repo.insert()

      %{category: category}
    end

    test "is valid with required fields", %{category: category} do
      changeset =
        Product.changeset(%Product{}, %{
          name: "Espresso",
          category_id: category.id
        })

      assert changeset.valid?
    end

    test "requires a name", %{category: category} do
      changeset =
        Product.changeset(%Product{}, %{
          category_id: category.id
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires a category_id" do
      changeset = Product.changeset(%Product{}, %{name: "Espresso"})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).category_id
    end

    test "allows description to be optional", %{category: category} do
      changeset =
        Product.changeset(%Product{}, %{
          name: "Espresso",
          category_id: category.id
        })

      assert changeset.valid?
      assert get_change(changeset, :description) == nil

      changeset_with_description =
        Product.changeset(%Product{}, %{
          name: "Espresso",
          description: "A strong shot of coffee",
          category_id: category.id
        })

      assert changeset_with_description.valid?
      assert get_change(changeset_with_description, :description) == "A strong shot of coffee"
    end

    test "defaults available to true", %{category: category} do
      assert {:ok, product} =
               %Product{}
               |> Product.changeset(%{name: "Espresso", category_id: category.id})
               |> Repo.insert()

      assert product.available == true
    end

    test "belongs to a category", %{category: category} do
      assert {:ok, product} =
               %Product{}
               |> Product.changeset(%{name: "Espresso", category_id: category.id})
               |> Repo.insert()

      product = Repo.preload(product, :category)

      assert product.category.id == category.id
      assert product.category.name == "HOT"
    end
  end
end
