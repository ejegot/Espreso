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

  defp insert_category!(name) do
    %Category{}
    |> Category.changeset(%{name: name})
    |> Repo.insert!()
  end

  describe "list_products_for_availability/0 and update_availability_as/3" do
    test "includes unavailable products and preserves category order" do
      hot = insert_category!("HOT")
      cold = insert_category!("COLD")
      insert_product!(hot, "Espresso", true, [{nil, "75"}])
      insert_product!(hot, "Secret Blend", false, [{nil, "999"}])
      insert_product!(cold, "Hazelnut", false, [{"16oz", "180"}])

      names =
        Menu.list_products_for_availability()
        |> Enum.map(& &1.name)

      assert names == ["HOT", "COLD"]

      hot_board =
        Menu.list_products_for_availability()
        |> Enum.find(&(&1.name == "HOT"))

      assert Enum.map(hot_board.products, & &1.name) == ["Espresso", "Secret Blend"]
      assert Enum.any?(hot_board.products, &(&1.name == "Secret Blend" and &1.available == false))
    end

    test "manager and owner can toggle availability; barista is denied" do
      hot = insert_category!("HOT")
      product = insert_product!(hot, "Espresso", true, [{nil, "75"}])

      owner = register!("Owner", "owner.avail@test.local", "owner")
      manager = register!("Manager", "manager.avail@test.local", "manager")
      barista = register!("Staff", "staff.avail@test.local", "barista")

      assert {:ok, unavailable} = Menu.update_availability_as(manager, product.id, false)
      assert unavailable.available == false

      hot_after_86 = Menu.list_menu() |> Enum.find(&(&1.name == "HOT"))
      refute hot_after_86 && Enum.any?(hot_after_86.products, &(&1.id == product.id))

      assert {:ok, available} = Menu.update_availability_as(owner, product.id, true)
      assert available.available == true

      hot_restored = Menu.list_menu() |> Enum.find(&(&1.name == "HOT"))
      assert hot_restored
      assert Enum.any?(hot_restored.products, &(&1.id == product.id))

      assert {:error, :unauthorized} = Menu.update_availability_as(barista, product.id, false)
      assert Repo.get!(Product, product.id).available == true
    end
  end

  defp register!(name, email, role) do
    {:ok, user} =
      Espreso.Accounts.register_user(%{
        name: name,
        email: email,
        password: "password123",
        role: role
      })

    user
  end

  describe "public_url/0" do
    test "returns the configured public menu URL for QR deployment" do
      assert Menu.public_url() == "http://localhost:4000/menu"
      assert String.ends_with?(Menu.public_url(), "/menu")
    end
  end

  describe "product_image/2" do
    test "returns a named CoffeeSpot photo for known items" do
      assert Menu.product_image("HOT", "Espresso") ==
               "/images/coffeespot/coffee-espresso-01.jpg"

      assert Menu.product_image("FOOD", "Beef Tapa") ==
               "/images/coffeespot/IMG_3464.JPG"

      assert Menu.product_image("COLD", "Strawberry Matcha") ==
               "/images/coffeespot/IMG_3467.JPG"
    end

    test "returns a category fallback for unknown item names" do
      src = Menu.product_image("SODA", "Mystery Fizz")

      assert src in [
               "/images/coffeespot/menu-drink-01.jpg",
               "/images/coffeespot/IMG_3481.JPG"
             ]
    end
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
