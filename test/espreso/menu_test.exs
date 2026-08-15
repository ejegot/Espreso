defmodule Espreso.MenuTest do
  use Espreso.DataCase, async: true

  alias Espreso.Menu
  alias Espreso.Menu.{Category, Product, ProductPrice}
  alias Espreso.Repo

  describe "list_menu/0" do
    test "groups FOOD products into subcategories in order" do
      food = insert_category!("FOOD")

      insert_product!(food, "Red Velvet", true, [{nil, "75"}])
      insert_product!(food, "Chicken Flakes", true, [{nil, "179"}])
      insert_product!(food, "Solo Fries", true, [{nil, "99"}])
      insert_product!(food, "Choco Chip Cookies", true, [{nil, "65"}])

      food_menu =
        Menu.list_menu()
        |> Enum.find(&(&1.name == "FOOD"))

      assert Enum.map(food_menu.groups, & &1.name) == [
               "Rice Meal",
               "Appetizers",
               "Muffins",
               "Cakes / Breads"
             ]

      assert Enum.map(hd(food_menu.groups).products, & &1.name) == ["Chicken Flakes"]
      assert Enum.map(Enum.at(food_menu.groups, 1).products, & &1.name) == ["Solo Fries"]
      assert Enum.map(Enum.at(food_menu.groups, 2).products, & &1.name) == ["Red Velvet"]
      assert Enum.map(Enum.at(food_menu.groups, 3).products, & &1.name) == ["Choco Chip Cookies"]
    end

    test "does not add subcategory headings for drink categories" do
      hot = insert_category!("HOT")
      insert_product!(hot, "Espresso", true, [{nil, "75"}])

      hot_menu =
        Menu.list_menu()
        |> Enum.find(&(&1.name == "HOT"))

      assert [%{name: nil, products: [%{name: "Espresso"}]}] = hot_menu.groups
    end

    test "excludes unavailable products" do
      hot = insert_category!("HOT")
      insert_product!(hot, "Espresso", true, [{nil, "75"}])
      insert_product!(hot, "Secret Blend", false, [{nil, "999"}])

      hot_menu =
        Menu.list_menu()
        |> Enum.find(&(&1.name == "HOT"))

      assert Enum.map(hot_menu.products, & &1.name) == ["Espresso"]
    end

    test "omits empty FOOD subgroups when all products are unavailable" do
      food = insert_category!("FOOD")
      insert_product!(food, "Chicken Flakes", true, [{nil, "179"}])
      insert_product!(food, "Solo Fries", false, [{nil, "99"}])
      insert_product!(food, "Beef Nachos", false, [{nil, "249"}])

      food_menu =
        Menu.list_menu()
        |> Enum.find(&(&1.name == "FOOD"))

      assert Enum.map(food_menu.groups, & &1.name) == ["Rice Meal"]
      assert Enum.map(hd(food_menu.groups).products, & &1.name) == ["Chicken Flakes"]
    end

    test "omits categories when all products are unavailable" do
      hot = insert_category!("HOT")
      cold = insert_category!("COLD")
      insert_product!(hot, "Espresso", true, [{nil, "75"}])
      insert_product!(cold, "Hazelnut", false, [{"16oz", "180"}])

      names =
        Menu.list_menu()
        |> Enum.map(& &1.name)

      assert names == ["HOT"]
      refute "COLD" in names
    end
  end

  describe "update_product_availability/2" do
    setup do
      category = insert_category!("HOT")
      %{category: category}
    end

    test "sets an available product to false", %{category: category} do
      product = insert_product!(category, "Espresso", true, [{nil, "75"}])

      assert {:ok, updated} = Menu.update_product_availability(product, false)
      assert updated.available == false
      assert Repo.get!(Product, product.id).available == false
    end

    test "sets an unavailable product to true", %{category: category} do
      product = insert_product!(category, "Espresso", false, [{nil, "75"}])

      assert {:ok, updated} = Menu.update_product_availability(product, true)
      assert updated.available == true
      assert Repo.get!(Product, product.id).available == true
    end

    test "returns the persisted product", %{category: category} do
      product = insert_product!(category, "Espresso", true, [{nil, "75"}])

      assert {:ok, updated} = Menu.update_product_availability(product, false)
      assert %Product{} = updated
      assert updated.id == product.id
      assert updated.available == false
    end

    test "returns an error changeset for invalid availability", %{category: category} do
      product = insert_product!(category, "Espresso", true, [{nil, "75"}])

      assert {:error, changeset} = Menu.update_product_availability(product, "maybe")
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).available
      assert Repo.get!(Product, product.id).available == true
    end
  end

  defp insert_category!(name) do
    %Category{}
    |> Category.changeset(%{name: name})
    |> Repo.insert!()
  end

  defp insert_product!(category, name, available, prices) do
    product =
      %Product{}
      |> Product.changeset(%{
        name: name,
        category_id: category.id,
        available: available
      })
      |> Repo.insert!()

    Enum.each(prices, fn {size, price} ->
      %ProductPrice{}
      |> ProductPrice.changeset(%{
        product_id: product.id,
        size: size,
        price: Decimal.new(price)
      })
      |> Repo.insert!()
    end)

    product
  end
end
