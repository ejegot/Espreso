defmodule Espreso.Menu do
  @moduledoc """
  The Menu context for loading customer-facing menu data.
  """

  import Ecto.Query

  alias Espreso.Repo
  alias Espreso.Menu.Category

  @category_order ~w(HOT COLD FRAPPE SODA FOOD)

  @product_images %{
    {"HOT", "Espresso"} => "/images/coffeespot/coffee-espresso-01.jpg",
    {"HOT", "Double Espresso"} => "/images/coffeespot/coffee-espresso-01.jpg",
    {"HOT", "Americano"} => "/images/coffeespot/coffee-espresso-01.jpg",
    {"HOT", "Café Latte"} => "/images/coffeespot/IMG_3468.JPG",
    {"HOT", "Cappuccino"} => "/images/coffeespot/IMG_3468.JPG",
    {"HOT", "Spanish Latte"} => "/images/coffeespot/IMG_3478.JPG",
    {"HOT", "Mocha Latte"} => "/images/coffeespot/coffee-table-01.jpg",
    {"HOT", "Caramel Macchiato"} => "/images/coffeespot/IMG_3458.JPG",
    {"HOT", "Butter Scotch"} => "/images/coffeespot/IMG_3458.JPG",
    {"HOT", "Matcha Latte"} => "/images/coffeespot/IMG_3471.JPG",
    {"HOT", "Hot Belagio Chocolate"} => "/images/coffeespot/coffee-table-01.jpg",
    {"COLD", "Americano"} => "/images/coffeespot/menu-drink-01.jpg",
    {"COLD", "Café Latte"} => "/images/coffeespot/cold-signature-01.jpg",
    {"COLD", "Mocha Latte"} => "/images/coffeespot/cold-detail-01.jpg",
    {"COLD", "Hazelnut"} => "/images/coffeespot/cold-table-01.jpg",
    {"COLD", "Macadamia"} => "/images/coffeespot/menu-drink-01.jpg",
    {"COLD", "Roasted Almond"} => "/images/coffeespot/cold-signature-01.jpg",
    {"COLD", "English Toffee"} => "/images/coffeespot/IMG_3458.JPG",
    {"COLD", "Caramel Macchiato"} => "/images/coffeespot/IMG_3458.JPG",
    {"COLD", "Spanish Latte"} => "/images/coffeespot/IMG_3478.JPG",
    {"COLD", "Butter Scotch"} => "/images/coffeespot/IMG_3458.JPG",
    {"COLD", "Matcha Caramel"} => "/images/coffeespot/IMG_3471.JPG",
    {"COLD", "Strawberry Matcha"} => "/images/coffeespot/IMG_3467.JPG",
    {"COLD", "Choco Berry"} => "/images/coffeespot/IMG_3481.JPG",
    {"FRAPPE", "Salted Caramel"} => "/images/coffeespot/IMG_3458.JPG",
    {"FRAPPE", "Mocha"} => "/images/coffeespot/cold-detail-01.jpg",
    {"FRAPPE", "Butter Scotch"} => "/images/coffeespot/IMG_3458.JPG",
    {"FRAPPE", "Mocha Crumble"} => "/images/coffeespot/cold-detail-01.jpg",
    {"FRAPPE", "Biscoff"} => "/images/coffeespot/IMG_3483.JPG",
    {"FRAPPE", "Cookies & Cream"} => "/images/coffeespot/IMG_3479.JPG",
    {"FRAPPE", "Matcha"} => "/images/coffeespot/IMG_3471.JPG",
    {"FRAPPE", "Double Chocolate"} => "/images/coffeespot/IMG_3481.JPG",
    {"FRAPPE", "Vanilla Bean Hazelnut"} => "/images/coffeespot/cold-signature-01.jpg",
    {"FRAPPE", "Strawberry"} => "/images/coffeespot/IMG_3467.JPG",
    {"SODA", "Tropical Passion Fruit"} => "/images/coffeespot/menu-drink-01.jpg",
    {"SODA", "Green Apple Campaign"} => "/images/coffeespot/IMG_3481.JPG",
    {"SODA", "Minty Peach"} => "/images/coffeespot/menu-drink-01.jpg",
    {"SODA", "Scarlet Berry"} => "/images/coffeespot/IMG_3481.JPG",
    {"SODA", "Majestic Mango"} => "/images/coffeespot/menu-drink-01.jpg",
    {"SODA", "Peach Berry"} => "/images/coffeespot/IMG_3481.JPG",
    {"SODA", "Hummingbird"} => "/images/coffeespot/menu-drink-01.jpg",
    {"FOOD", "Chicken Flakes"} => "/images/coffeespot/IMG_3459.JPG",
    {"FOOD", "Beef Tapa"} => "/images/coffeespot/IMG_3464.JPG",
    {"FOOD", "Corned Beef"} => "/images/coffeespot/IMG_3480.JPG",
    {"FOOD", "Spam"} => "/images/coffeespot/IMG_3487.JPG",
    {"FOOD", "Pork Liempo"} => "/images/coffeespot/food-savory-01.jpg",
    {"FOOD", "Spam Musubi"} => "/images/coffeespot/IMG_3487.JPG",
    {"FOOD", "Nugget"} => "/images/coffeespot/food-savory-01.jpg",
    {"FOOD", "Solo Fries"} => "/images/coffeespot/food-savory-01.jpg",
    {"FOOD", "Fries w/ Nuggets"} => "/images/coffeespot/food-savory-01.jpg",
    {"FOOD", "Beef Nachos"} => "/images/coffeespot/IMG_3465.JPG",
    {"FOOD", "Quesadillas"} => "/images/coffeespot/IMG_3472.JPG",
    {"FOOD", "Chicken & Chips"} => "/images/coffeespot/IMG_3473.JPG",
    {"FOOD", "Spam & Chips"} => "/images/coffeespot/IMG_3473.JPG",
    {"FOOD", "BNN Cream Cheese"} => "/images/coffeespot/IMG_3485.JPG",
    {"FOOD", "BNN Choco Overload"} => "/images/coffeespot/IMG_3484.JPG",
    {"FOOD", "BNN Biscoff"} => "/images/coffeespot/IMG_3483.JPG",
    {"FOOD", "Choco Chips"} => "/images/coffeespot/IMG_3482.JPG",
    {"FOOD", "Red Velvet"} => "/images/coffeespot/IMG_3460.JPG",
    {"FOOD", "Dark Choco Dream Cake"} => "/images/coffeespot/IMG_3461.JPG",
    {"FOOD", "Choco Chip Cookies"} => "/images/coffeespot/IMG_3479.JPG",
    {"FOOD", "BNN Moist Slice"} => "/images/coffeespot/IMG_3462.JPG",
    {"FOOD", "Choco Moist Slice"} => "/images/coffeespot/IMG_3461.JPG",
    {"FOOD", "Carrot Moist Slice"} => "/images/coffeespot/pastry-signature-01.jpg"
  }

  @category_images %{
    "HOT" => [
      "/images/coffeespot/coffee-espresso-01.jpg",
      "/images/coffeespot/IMG_3468.JPG",
      "/images/coffeespot/coffee-table-01.jpg"
    ],
    "COLD" => [
      "/images/coffeespot/cold-signature-01.jpg",
      "/images/coffeespot/menu-drink-01.jpg",
      "/images/coffeespot/IMG_3481.JPG",
      "/images/coffeespot/cold-table-01.jpg"
    ],
    "FRAPPE" => [
      "/images/coffeespot/IMG_3458.JPG",
      "/images/coffeespot/cold-signature-01.jpg",
      "/images/coffeespot/IMG_3481.JPG"
    ],
    "SODA" => [
      "/images/coffeespot/menu-drink-01.jpg",
      "/images/coffeespot/IMG_3481.JPG"
    ],
    "FOOD" => [
      "/images/coffeespot/food-savory-01.jpg",
      "/images/coffeespot/pastry-signature-01.jpg",
      "/images/coffeespot/food-signature-01.jpg",
      "/images/coffeespot/IMG_3472.JPG"
    ]
  }

  @food_subcategories [
    {"Rice Meal",
     [
       "Chicken Flakes",
       "Beef Tapa",
       "Corned Beef",
       "Spam",
       "Pork Liempo",
       "Spam Musubi",
       "Nugget"
     ]},
    {"Appetizers",
     [
       "Solo Fries",
       "Fries w/ Nuggets",
       "Beef Nachos",
       "Quesadillas",
       "Chicken & Chips",
       "Spam & Chips"
     ]},
    {"Muffins",
     [
       "BNN Cream Cheese",
       "BNN Choco Overload",
       "BNN Biscoff",
       "Choco Chips",
       "Red Velvet"
     ]},
    {"Cakes / Breads",
     [
       "Dark Choco Dream Cake",
       "Choco Chip Cookies",
       "BNN Moist Slice",
       "Choco Moist Slice",
       "Carrot Moist Slice"
     ]}
  ]

  @doc """
  Returns categories in menu order, each with available products, prices,
  and display groups (FOOD is split into subcategories).
  """
  def list_menu do
    Category
    |> preload(products: :product_prices)
    |> Repo.all()
    |> Enum.map(&filter_available_products/1)
    |> Enum.reject(&(&1.products == []))
    |> Enum.sort_by(&category_position/1)
    |> Enum.map(&decorate_category/1)
  end

  @doc """
  Absolute public URL for the CoffeeSpot QR landing page (`/`).

  Configured as `:public_menu_url` (env `PUBLIC_MENU_URL`).
  Development falls back to `http://localhost:4000/`.
  """
  def public_url do
    Application.fetch_env!(:espreso, :public_menu_url)
  end

  defp filter_available_products(category) do
    products =
      category.products
      |> Enum.filter(& &1.available)
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn product ->
        prices =
          product.product_prices
          |> Enum.sort_by(&price_sort_key/1)

        %{product | product_prices: prices}
      end)

    %{category | products: products}
  end

  defp decorate_category(category) do
    groups =
      case category.name do
        "FOOD" -> food_groups(category.products)
        _other -> [%{name: nil, products: category.products}]
      end

    %{
      name: category.name,
      products: category.products,
      groups: groups
    }
  end

  defp food_groups(products) do
    products_by_name = Map.new(products, &{&1.name, &1})

    @food_subcategories
    |> Enum.map(fn {group_name, product_names} ->
      grouped_products =
        product_names
        |> Enum.map(&Map.get(products_by_name, &1))
        |> Enum.reject(&is_nil/1)

      %{name: group_name, products: grouped_products}
    end)
    |> Enum.reject(fn group -> group.products == [] end)
  end

  defp category_position(%{name: name}) do
    Enum.find_index(@category_order, &(&1 == name)) || length(@category_order)
  end

  defp price_sort_key(%{size: nil}), do: {0, ""}
  defp price_sort_key(%{size: size}), do: {1, size}

  @doc """
  Public image path for a menu item. Named CoffeeSpot photos first,
  then a stable category fallback so every card has a photo.
  """
  def product_image(category_name, product_name)
      when is_binary(category_name) and is_binary(product_name) do
    Map.get(@product_images, {category_name, product_name}) ||
      category_fallback_image(category_name, product_name)
  end

  defp category_fallback_image(category_name, product_name) do
    pool = Map.get(@category_images, category_name) || @category_images["HOT"]
    Enum.at(pool, :erlang.phash2(product_name, length(pool)))
  end

  @doc """
  Formats a price as Philippine peso.

  Whole peso amounts omit decimals (₱75). Fractional amounts use two decimals (₱75.50).
  """
  def format_price(price) do
    rounded = Decimal.round(price, 2)

    formatted =
      if Decimal.equal?(rounded, Decimal.round(rounded, 0)) do
        rounded
        |> Decimal.round(0)
        |> Decimal.to_string(:normal)
      else
        rounded
        |> Decimal.to_string(:normal)
        |> ensure_two_decimals()
      end

    "₱#{formatted}"
  end

  defp ensure_two_decimals(string) do
    case String.split(string, ".") do
      [whole] -> "#{whole}.00"
      [whole, fraction] -> "#{whole}.#{String.pad_trailing(fraction, 2, "0")}"
    end
  end
end
