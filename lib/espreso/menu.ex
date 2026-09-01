defmodule Espreso.Menu do
  @moduledoc """
  The Menu context for loading customer-facing menu data.
  """

  import Ecto.Query

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.Repo
  alias Espreso.Menu.{Category, Product}

  @category_order ~w(HOT COLD FRAPPE SODA FOOD)

  @product_images %{
    {"HOT", "Espresso"} => "/images/coffeespot/coffee-espresso-01.jpg",
    {"HOT", "Double Espresso"} => "/images/coffeespot/coffee-detail-01.jpg",
    {"HOT", "Americano"} => "/images/coffeespot/coffee-table-01.jpg",
    {"HOT", "Café Latte"} => "/images/coffeespot/IMG_3468.JPG",
    {"HOT", "Cappuccino"} => "/images/coffeespot/IMG_3468.JPG",
    {"HOT", "Spanish Latte"} => "/images/coffeespot/IMG_3478.JPG",
    {"HOT", "Mocha Latte"} => "/images/coffeespot/IMG_3468.JPG",
    {"HOT", "Caramel Macchiato"} => "/images/coffeespot/IMG_3458.JPG",
    {"HOT", "Butter Scotch"} => "/images/coffeespot/IMG_3469.JPG",
    {"HOT", "Matcha Latte"} => "/images/coffeespot/IMG_3471.JPG",
    {"HOT", "Hot Belagio Chocolate"} => "/images/coffeespot/IMG_3477.JPG",
    {"COLD", "Americano"} => "/images/coffeespot/menu-drink-01.jpg",
    {"COLD", "Café Latte"} => "/images/coffeespot/cold-signature-01.jpg",
    {"COLD", "Mocha Latte"} => "/images/coffeespot/cold-detail-01.jpg",
    {"COLD", "Hazelnut"} => "/images/coffeespot/cold-table-01.jpg",
    {"COLD", "Macadamia"} => "/images/coffeespot/menu-drink-01.jpg",
    {"COLD", "Roasted Almond"} => "/images/coffeespot/cold-signature-01.jpg",
    {"COLD", "English Toffee"} => "/images/coffeespot/cold-detail-01.jpg",
    {"COLD", "Caramel Macchiato"} => "/images/coffeespot/cold-signature-01.jpg",
    {"COLD", "Spanish Latte"} => "/images/coffeespot/IMG_3478.JPG",
    {"COLD", "Butter Scotch"} => "/images/coffeespot/cold-table-01.jpg",
    {"COLD", "Matcha Caramel"} => "/images/coffeespot/IMG_3471.JPG",
    {"COLD", "Strawberry Matcha"} => "/images/coffeespot/IMG_3467.JPG",
    {"COLD", "Choco Berry"} => "/images/coffeespot/IMG_3481.JPG",
    {"COLD", "Iced Bellagio Choco"} => "/images/coffeespot/drink-iced-bellagio-choco.png",
    {"FRAPPE", "Salted Caramel"} => "/images/coffeespot/IMG_3458.JPG",
    {"FRAPPE", "Mocha"} => "/images/coffeespot/cold-detail-01.jpg",
    {"FRAPPE", "Butter Scotch"} => "/images/coffeespot/IMG_3469.JPG",
    {"FRAPPE", "Mocha Crumble"} => "/images/coffeespot/cold-detail-01.jpg",
    {"FRAPPE", "Biscoff"} => "/images/coffeespot/drink-biscoff-frappe.png",
    {"FRAPPE", "Cookies & Cream"} => "/images/coffeespot/IMG_3479.JPG",
    {"FRAPPE", "Matcha"} => "/images/coffeespot/IMG_3471.JPG",
    {"FRAPPE", "Double Chocolate"} => "/images/coffeespot/drink-double-chocolate.png",
    {"FRAPPE", "Vanilla Bean Hazelnut"} => "/images/coffeespot/cold-signature-01.jpg",
    {"FRAPPE", "Strawberry"} => "/images/coffeespot/IMG_3467.JPG",
    {"SODA", "Tropical Passion Fruit"} => "/images/coffeespot/soda-signature-01.jpg",
    {"SODA", "Green Apple Campagna"} => "/images/coffeespot/drink-green-apple-campagna.png",
    {"SODA", "Minty Peach"} => "/images/coffeespot/IMG_3457.JPG",
    {"SODA", "Scarlet Berry"} => "/images/coffeespot/drink-scarlet-berry.png",
    {"SODA", "Majestic Mango"} => "/images/coffeespot/soda-signature-01.jpg",
    {"SODA", "Peach Berry"} => "/images/coffeespot/IMG_3477.JPG",
    {"SODA", "Hummingbird"} => "/images/coffeespot/IMG_3477.JPG",
    {"FOOD", "Chicken Flakes"} => "/images/coffeespot/IMG_3459.JPG",
    {"FOOD", "Beef Tapa"} => "/images/coffeespot/IMG_3464.JPG",
    {"FOOD", "Corned Beef"} => "/images/coffeespot/IMG_3480.JPG",
    {"FOOD", "Spam"} => "/images/coffeespot/IMG_3487.JPG",
    {"FOOD", "Pork Liempo"} => "/images/coffeespot/food-savory-01.jpg",
    {"FOOD", "Spam Musubi"} => "/images/coffeespot/food-spam-musubi.png",
    {"FOOD", "Nugget"} => "/images/coffeespot/IMG_3474.JPG",
    {"FOOD", "Solo Fries"} => "/images/coffeespot/food-savory-01.jpg",
    {"FOOD", "Fries w/ Nuggets"} => "/images/coffeespot/IMG_3474.JPG",
    {"FOOD", "Beef Nachos"} => "/images/coffeespot/IMG_3465.JPG",
    {"FOOD", "Quesadillas"} => "/images/coffeespot/IMG_3472.JPG",
    {"FOOD", "Chicken & Chips"} => "/images/coffeespot/IMG_3473.JPG",
    {"FOOD", "Spam & Chips"} => "/images/coffeespot/IMG_3473.JPG",
    {"FOOD", "Slow-Roasted Chicken Sourdough"} =>
      "/images/coffeespot/food-slow-roasted-chicken-sourdough.png",
    {"FOOD", "Golden Egg Royale"} => "/images/coffeespot/food-golden-egg-royale.png",
    {"FOOD", "Tuna Royale Baguette"} => "/images/coffeespot/food-tuna-royale-baguette.png",
    {"FOOD", "BNN Cream Cheese"} => "/images/coffeespot/IMG_3485.JPG",
    {"FOOD", "BNN Choco Overload"} => "/images/coffeespot/IMG_3484.JPG",
    {"FOOD", "BNN Biscoff"} => "/images/coffeespot/IMG_3483.JPG",
    {"FOOD", "Choco Chips"} => "/images/coffeespot/IMG_3482.JPG",
    {"FOOD", "Red Velvet"} => "/images/coffeespot/IMG_3460.JPG",
    {"FOOD", "Dark Choco Dream Cake"} => "/images/coffeespot/IMG_3461.JPG",
    {"FOOD", "Choco Chip Cookies"} => "/images/coffeespot/IMG_3479.JPG",
    {"FOOD", "BNN Moist Slice"} => "/images/coffeespot/IMG_3462.JPG",
    {"FOOD", "Choco Moist Slice"} => "/images/coffeespot/IMG_3461.JPG",
    {"FOOD", "Carrot Moist Slice"} => "/images/coffeespot/pastry-signature-01.jpg",
    {"FOOD", "Belgian Waffles"} => "/images/coffeespot/food-belgian-waffles.png",
    {"FOOD", "Chocolate Almond Waffles"} => "/images/coffeespot/food-chocolate-almond-waffles.png"
  }

  @category_images %{
    "HOT" => [
      "/images/coffeespot/coffee-espresso-01.jpg",
      "/images/coffeespot/IMG_3468.JPG",
      "/images/coffeespot/coffee-table-01.jpg",
      "/images/coffeespot/coffee-detail-01.jpg"
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
      "/images/coffeespot/IMG_3481.JPG",
      "/images/coffeespot/IMG_3469.JPG"
    ],
    "SODA" => [
      "/images/coffeespot/soda-signature-01.jpg",
      "/images/coffeespot/IMG_3477.JPG",
      "/images/coffeespot/IMG_3457.JPG"
    ],
    "FOOD" => [
      "/images/coffeespot/food-savory-01.jpg",
      "/images/coffeespot/pastry-signature-01.jpg",
      "/images/coffeespot/food-signature-01.jpg",
      "/images/coffeespot/IMG_3472.JPG",
      "/images/coffeespot/IMG_3474.JPG"
    ]
  }

  @product_descriptions %{
    # HOT
    {"HOT", "Espresso"} => "A bold, concentrated shot of pure coffee with a rich caramel crema.",
    {"HOT", "Double Espresso"} => "Two shots of intense espresso for an extra kick of energy.",
    {"HOT", "Americano"} => "Smooth espresso diluted with hot water for a clean, bold flavor.",
    {"HOT", "Café Latte"} => "Velvety steamed milk blended with a shot of rich espresso.",
    {"HOT", "Cappuccino"} => "Equal parts espresso, steamed milk, and silky foam — a classic.",
    {"HOT", "Spanish Latte"} =>
      "Espresso sweetened with condensed milk for a creamy, indulgent sip.",
    {"HOT", "Mocha Latte"} => "Rich chocolate meets espresso and steamed milk — a cozy favorite.",
    {"HOT", "Caramel Macchiato"} =>
      "Espresso marked with vanilla milk and drizzled with buttery caramel.",
    {"HOT", "Butter Scotch"} =>
      "Sweet butterscotch syrup stirred into warm espresso and steamed milk.",
    {"HOT", "Matcha Latte"} => "Premium Japanese matcha whisked with creamy steamed milk.",
    {"HOT", "Hot Belagio Chocolate"} =>
      "A luxuriously thick and creamy European-style hot chocolate.",
    # COLD
    {"COLD", "Americano"} => "Chilled espresso over ice for a refreshing, no-fuss coffee.",
    {"COLD", "Café Latte"} => "Espresso poured over ice and topped with cold, creamy milk.",
    {"COLD", "Mocha Latte"} =>
      "Iced espresso swirled with chocolate and milk — smooth and sweet.",
    {"COLD", "Hazelnut"} => "Nutty hazelnut flavor blended into iced espresso and cold milk.",
    {"COLD", "Macadamia"} => "A buttery macadamia twist on classic iced coffee.",
    {"COLD", "Roasted Almond"} => "Toasted almond notes layered into a chilled espresso drink.",
    {"COLD", "English Toffee"} => "Sweet toffee and espresso over ice — rich and satisfying.",
    {"COLD", "Caramel Macchiato"} =>
      "Iced vanilla milk with espresso and a caramel ribbon on top.",
    {"COLD", "Spanish Latte"} =>
      "Iced espresso with condensed milk — sweet, creamy, and refreshing.",
    {"COLD", "Butter Scotch"} => "Butterscotch and espresso over ice for a smooth, sweet treat.",
    {"COLD", "Matcha Caramel"} =>
      "Earthy matcha meets buttery caramel over ice — unique and delicious.",
    {"COLD", "Strawberry Matcha"} =>
      "Fresh strawberry layered with iced matcha — fruity and vibrant.",
    {"COLD", "Choco Berry"} => "Chocolate and mixed berry flavors blended into a chilled drink.",
    {"COLD", "Iced Bellagio Choco"} =>
      "Rich iced chocolate with Bellagio-style drizzle — cool, creamy, and indulgent.",
    # FRAPPE
    {"FRAPPE", "Salted Caramel"} =>
      "Sweet caramel with a hint of sea salt blended into a frosty frappe.",
    {"FRAPPE", "Mocha"} => "Chocolate and coffee blended with ice into a creamy, frozen treat.",
    {"FRAPPE", "Butter Scotch"} => "Rich butterscotch flavor in a thick, icy blended frappe.",
    {"FRAPPE", "Mocha Crumble"} => "Mocha frappe loaded with crunchy cookie crumble on top.",
    {"FRAPPE", "Biscoff"} =>
      "The beloved Biscoff cookie flavor blended into a smooth, spiced frappe.",
    {"FRAPPE", "Cookies & Cream"} =>
      "Crushed cookies blended with vanilla cream — a dessert in a cup.",
    {"FRAPPE", "Matcha"} => "Premium matcha blended with ice and milk for a refreshing treat.",
    {"FRAPPE", "Double Chocolate"} =>
      "Double the chocolate, double the indulgence — thick and frosty.",
    {"FRAPPE", "Vanilla Bean Hazelnut"} =>
      "Real vanilla bean and hazelnut blended into a creamy frappe.",
    {"FRAPPE", "Strawberry"} => "Sweet strawberry blended into a pink, fruity frozen delight.",
    # SODA
    {"SODA", "Tropical Passion Fruit"} =>
      "Tangy passion fruit fizzing with sparkling soda — bright and tropical.",
    {"SODA", "Green Apple Campagna"} =>
      "Crisp green apple soda with a refreshing tart finish.",
    {"SODA", "Minty Peach"} => "Cool mint meets sweet peach in a sparkling, refreshing drink.",
    {"SODA", "Scarlet Berry"} => "A vibrant berry soda with a deep, fruity sweetness.",
    {"SODA", "Majestic Mango"} => "Sweet Philippine mango blended into a fizzy, golden soda.",
    {"SODA", "Peach Berry"} => "Juicy peach and mixed berries in a sparkling, fruity cooler.",
    {"SODA", "Hummingbird"} => "A house-special citrus and floral soda — light and uplifting.",
    # FOOD — Rice Meals
    {"FOOD", "Chicken Flakes"} =>
      "Tender shredded chicken served with garlic rice and a fried egg.",
    {"FOOD", "Beef Tapa"} =>
      "Sweet-cured beef strips with garlic rice and egg — a Filipino classic.",
    {"FOOD", "Corned Beef"} =>
      "Savory corned beef sautéed with onions, served with rice and egg.",
    {"FOOD", "Spam"} => "Pan-fried Spam slices with garlic rice and a sunny-side-up egg.",
    {"FOOD", "Pork Liempo"} => "Juicy grilled pork belly with garlic rice and a fried egg.",
    {"FOOD", "Spam Musubi"} => "Spam on sushi rice wrapped in nori — a quick, savory bite.",
    {"FOOD", "Nugget"} => "Golden crispy chicken nuggets served with your choice of dip.",
    # FOOD — Appetizers
    {"FOOD", "Solo Fries"} => "A generous serving of crispy, golden french fries.",
    {"FOOD", "Fries w/ Nuggets"} =>
      "Crispy fries paired with golden chicken nuggets — a perfect combo.",
    {"FOOD", "Beef Nachos"} => "Tortilla chips loaded with seasoned beef, cheese, and salsa.",
    {"FOOD", "Quesadillas"} =>
      "Grilled flour tortilla filled with melted cheese and savory filling.",
    {"FOOD", "Chicken & Chips"} => "Crispy chicken tenders served with a side of seasoned fries.",
    {"FOOD", "Spam & Chips"} => "Pan-fried Spam slices paired with crispy seasoned fries.",
    # FOOD — Sandwiches & Wraps
    {"FOOD", "Slow-Roasted Chicken Sourdough"} =>
      "Slow-marinated chicken, gently cooked to tender perfection, layered with melted cheese and roasted vegetables between golden, toasted sourdough.",
    {"FOOD", "Golden Egg Royale"} =>
      "Fluffy seasoned eggs wrapped in a warm, lightly toasted tortilla, served with fresh vegetables and a delicate savory finish.",
    {"FOOD", "Tuna Royale Baguette"} =>
      "Creamy seasoned tuna layered generously over a crisp, artisan baguette, finished with fresh herbs and a delicate savory touch.",
    # FOOD — Muffins
    {"FOOD", "BNN Cream Cheese"} => "Moist banana muffin topped with a rich cream cheese swirl.",
    {"FOOD", "BNN Choco Overload"} =>
      "Banana muffin loaded with chocolate chips and cocoa drizzle.",
    {"FOOD", "BNN Biscoff"} => "Banana muffin with Biscoff spread and cookie crumble topping.",
    {"FOOD", "Choco Chips"} => "A classic chocolate chip muffin — soft, warm, and sweet.",
    {"FOOD", "Red Velvet"} => "Rich red velvet muffin with a hint of cocoa and cream cheese.",
    # FOOD — Cakes / Breads
    {"FOOD", "Dark Choco Dream Cake"} =>
      "Dense, fudgy dark chocolate cake — a chocoholic's dream.",
    {"FOOD", "Choco Chip Cookies"} => "Freshly baked cookies packed with melty chocolate chips.",
    {"FOOD", "BNN Moist Slice"} =>
      "A thick slice of ultra-moist banana bread — homestyle comfort.",
    {"FOOD", "Choco Moist Slice"} => "Rich chocolate banana bread — soft, moist, and indulgent.",
    {"FOOD", "Carrot Moist Slice"} =>
      "Spiced carrot bread with a moist crumb and subtle sweetness.",
    {"FOOD", "Belgian Waffles"} =>
      "Golden Belgian waffles with butter and maple syrup — warm and comforting.",
    {"FOOD", "Chocolate Almond Waffles"} =>
      "Crisp waffles drizzled with chocolate and topped with almond slivers."
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
    {"Sandwiches & Wraps",
     [
       "Slow-Roasted Chicken Sourdough",
       "Golden Egg Royale",
       "Tuna Royale Baguette"
     ]},
    {"Muffins",
     [
       "Big Assorted Muffin"
     ]},
    {"Cakes / Breads",
     [
       "Dark Choco Dream Cake",
       "Choco Chip Cookies",
       "BNN Moist Slice",
       "Choco Moist Slice",
       "Carrot Moist Slice",
       "Belgian Waffles",
       "Chocolate Almond Waffles"
     ]}
  ]

  @sweets_subcategory_names ["Muffins", "Cakes / Breads"]

  @doc """
  Customer-facing Sweets filter names derived from FOOD muffin/cake/cookie items.

  Not a database category — used by the QR craving discovery layer.
  """
  def sweets_product_names do
    @food_subcategories
    |> Enum.filter(fn {group, _} -> group in @sweets_subcategory_names end)
    |> Enum.flat_map(fn {_, products} -> products end)
  end

  def sweets_product_name?(name) when is_binary(name) do
    name in sweets_product_names()
  end

  def sweets_product_name?(_), do: false

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
  Categories with ALL products (including unavailable), for the 86 board.

  Preserves category and product ordering used by the public menu.
  """
  def list_products_for_availability do
    Category
    |> preload(:products)
    |> Repo.all()
    |> Enum.map(fn category ->
      products =
        category.products
        |> Enum.sort_by(& &1.id)

      %{category | products: products}
    end)
    |> Enum.reject(&(&1.products == []))
    |> Enum.sort_by(&category_position/1)
  end

  @doc """
  Sets product availability when the actor has `:product_availability`.
  """
  def update_availability_as(%User{} = actor, product_id, available)
      when is_integer(product_id) and is_boolean(available) do
    with :ok <- Authorization.authorize(actor, :product_availability),
         %Product{} = product <- Repo.get(Product, product_id) do
      product
      |> Product.changeset(%{available: available})
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      {:error, :unauthorized} = err -> err
    end
  end

  def update_availability_as(%User{} = actor, %Product{} = product, available)
      when is_boolean(available) do
    update_availability_as(actor, product.id, available)
  end

  @doc """
  Absolute public URL for the CoffeeSpot QR menu landing page (`/menu`).

  Configured as `:public_menu_url` (env `PUBLIC_MENU_URL`).
  Development falls back to `http://localhost:4000/menu`.
  """
  def public_url do
    Application.fetch_env!(:espreso, :public_menu_url)
  end

  @doc """
  Returns display names for order lines whose products are missing or unavailable.

  Prefers `:product_id` on each line (Menu/POS carts). Lines without an id are
  resolved by exact product name when such products exist. Application-level
  check only — not a DB lock.
  """
  def unavailable_for_order_lines(lines) when is_list(lines) do
    ids =
      lines
      |> Enum.map(&line_product_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    products_by_id =
      if ids == [] do
        %{}
      else
        Product
        |> where([p], p.id in ^ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})
      end

    lines
    |> Enum.flat_map(fn line ->
      name = line_name(line)

      case line_product_id(line) do
        nil ->
          flags =
            Product
            |> where([p], p.name == ^name)
            |> select([p], p.available)
            |> Repo.all()

          cond do
            flags == [] -> []
            Enum.any?(flags, & &1) -> []
            true -> [name]
          end

        id ->
          case Map.fetch(products_by_id, id) do
            {:ok, %{available: true}} -> []
            {:ok, %{available: false}} -> [name]
            :error -> [name]
          end
      end
    end)
    |> Enum.uniq()
  end

  defp line_product_id(line) do
    case Map.get(line, :product_id) || Map.get(line, "product_id") do
      id when is_integer(id) -> id
      id when is_binary(id) -> String.to_integer(id)
      _ -> nil
    end
  end

  defp line_name(line) do
    Map.get(line, :name) || Map.get(line, "name") || "Item"
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
    products = Enum.map(category.products, &apply_description(&1, category.name))

    groups =
      case category.name do
        "FOOD" -> food_groups(products)
        _other -> [%{name: nil, products: products}]
      end

    %{
      name: category.name,
      products: products,
      groups: groups
    }
  end

  defp apply_description(product, category_name) do
    existing = product.description
    has_desc? = is_binary(existing) and String.trim(existing) != ""

    if has_desc? do
      product
    else
      desc = Map.get(@product_descriptions, {category_name, product.name}, "")
      %{product | description: desc}
    end
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
  Amounts of ₱1,000 and above include thousands separators (₱1,500).
  """
  def format_price(price) do
    rounded = Decimal.round(price, 2)

    formatted =
      if Decimal.equal?(rounded, Decimal.round(rounded, 0)) do
        rounded
        |> Decimal.round(0)
        |> Decimal.to_string(:normal)
        |> add_thousands_separator()
      else
        rounded
        |> Decimal.to_string(:normal)
        |> ensure_two_decimals()
        |> add_thousands_separator_to_amount()
      end

    "₱#{formatted}"
  end

  defp add_thousands_separator_to_amount(string) do
    case String.split(string, ".") do
      [whole, fraction] -> "#{add_thousands_separator(whole)}.#{fraction}"
      [whole] -> add_thousands_separator(whole)
    end
  end

  defp add_thousands_separator(whole) when is_binary(whole) do
    whole
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp ensure_two_decimals(string) do
    case String.split(string, ".") do
      [whole] -> "#{whole}.00"
      [whole, fraction] -> "#{whole}.#{String.pad_trailing(fraction, 2, "0")}"
    end
  end
end
