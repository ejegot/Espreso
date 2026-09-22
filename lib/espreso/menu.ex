defmodule Espreso.Menu do
  @moduledoc """
  The Menu context for loading customer-facing menu data.
  """

  import Ecto.Query

  alias Espreso.Accounts.Authorization
  alias Espreso.Accounts.User
  alias Espreso.Repo
  alias Espreso.Menu.{Category, Product, ProductPhoto, ProductPrice}

  @category_order ~w(HOT COLD FRAPPE SODA FOOD)
  @photo_max_bytes 3_000_000
  @photo_types ~w(image/jpeg image/png image/webp)

  @product_images %{
    {"HOT", "Espresso"} => "/images/coffeespot/gen-hot-espresso.png",
    {"HOT", "Double Espresso"} => "/images/coffeespot/gen-hot-double-espresso.png",
    {"HOT", "Americano"} => "/images/coffeespot/gen-hot-americano.png",
    {"HOT", "Café Latte"} => "/images/coffeespot/gen-hot-cafe-latte.png",
    {"HOT", "Cappuccino"} => "/images/coffeespot/gen-hot-cappuccino.png",
    {"HOT", "Spanish Latte"} => "/images/coffeespot/gen-hot-spanish-latte.png",
    {"HOT", "Mocha Latte"} => "/images/coffeespot/gen-hot-mocha-latte.png",
    {"HOT", "Caramel Macchiato"} => "/images/coffeespot/gen-hot-caramel-macchiato.png",
    {"HOT", "Butter Scotch"} => "/images/coffeespot/gen-hot-butter-scotch.png",
    {"HOT", "Matcha Latte"} => "/images/coffeespot/gen-hot-matcha-latte.png",
    {"HOT", "Hot Belagio Chocolate"} => "/images/coffeespot/gen-hot-belagio-chocolate.png",
    {"HOT", "Signature Tablea"} => "/images/coffeespot/signature-pure-tableya-portrait.jpg",
    {"COLD", "Americano"} => "/images/coffeespot/gen-cold-americano.png",
    {"COLD", "Café Latte"} => "/images/coffeespot/gen-cold-cafe-latte.png",
    {"COLD", "Mocha Latte"} => "/images/coffeespot/gen-cold-mocha-latte.png",
    {"COLD", "Hazelnut"} => "/images/coffeespot/gen-cold-hazelnut.png",
    {"COLD", "Macadamia"} => "/images/coffeespot/gen-cold-macadamia.png",
    {"COLD", "Roasted Almond"} => "/images/coffeespot/gen-cold-roasted-almond.png",
    {"COLD", "English Toffee"} => "/images/coffeespot/gen-cold-english-toffee.png",
    {"COLD", "Caramel Macchiato"} => "/images/coffeespot/gen-cold-caramel-macchiato.png",
    {"COLD", "Spanish Latte"} => "/images/coffeespot/gen-cold-spanish-latte.png",
    {"COLD", "Butter Scotch"} => "/images/coffeespot/gen-cold-butter-scotch.png",
    {"COLD", "Matcha Caramel"} => "/images/coffeespot/gen-cold-matcha-caramel.png",
    {"COLD", "Strawberry Matcha"} => "/images/coffeespot/gen-cold-strawberry-matcha.png",
    {"COLD", "Choco Berry"} => "/images/coffeespot/gen-cold-choco-berry.png",
    {"COLD", "Iced Bellagio Choco"} => "/images/coffeespot/gen-cold-bellagio-choco.png",
    {"FRAPPE", "Salted Caramel"} => "/images/coffeespot/gen-frappe-salted-caramel.png",
    {"FRAPPE", "Mocha"} => "/images/coffeespot/gen-frappe-mocha.png",
    {"FRAPPE", "Butter Scotch"} => "/images/coffeespot/gen-frappe-butter-scotch.png",
    {"FRAPPE", "Mocha Crumble"} => "/images/coffeespot/gen-frappe-mocha-crumble.png",
    {"FRAPPE", "Biscoff"} => "/images/coffeespot/gen-frappe-biscoff.png",
    {"FRAPPE", "Cookies & Cream"} => "/images/coffeespot/gen-frappe-cookies-cream.png",
    {"FRAPPE", "Matcha"} => "/images/coffeespot/gen-frappe-matcha.png",
    {"FRAPPE", "Double Chocolate"} => "/images/coffeespot/gen-frappe-double-chocolate.png",
    {"FRAPPE", "Vanilla Bean Hazelnut"} => "/images/coffeespot/gen-frappe-vanilla-hazelnut.png",
    {"FRAPPE", "Strawberry"} => "/images/coffeespot/gen-frappe-strawberry.png",
    {"SODA", "Tropical Passion Fruit"} => "/images/coffeespot/gen-soda-tropical-passion.png",
    {"SODA", "Green Apple Campagna"} => "/images/coffeespot/gen-soda-green-apple.png",
    {"SODA", "Minty Peach"} => "/images/coffeespot/gen-soda-minty-peach.png",
    {"SODA", "Scarlet Berry"} => "/images/coffeespot/gen-soda-scarlet-berry.png",
    {"SODA", "Majestic Mango"} => "/images/coffeespot/gen-soda-majestic-mango.png",
    {"SODA", "Peach Berry"} => "/images/coffeespot/gen-soda-peach-berry.png",
    {"SODA", "Hummingbird"} => "/images/coffeespot/gen-soda-hummingbird.png",
    {"FOOD", "Chicken Flakes"} => "/images/coffeespot/gen-food-chicken-flakes.png",
    {"FOOD", "Beef Tapa"} => "/images/coffeespot/gen-food-beef-tapa.png",
    {"FOOD", "Corned Beef"} => "/images/coffeespot/gen-food-corned-beef.png",
    {"FOOD", "Spam"} => "/images/coffeespot/gen-food-spam.png",
    {"FOOD", "Pork Liempo"} => "/images/coffeespot/gen-food-pork-liempo.png",
    {"FOOD", "Spam Musubi"} => "/images/coffeespot/gen-food-spam-musubi.png",
    {"FOOD", "Nugget"} => "/images/coffeespot/gen-food-nugget.png",
    {"FOOD", "Solo Fries"} => "/images/coffeespot/gen-food-solo-fries.png",
    {"FOOD", "Fries w/ Nuggets"} => "/images/coffeespot/gen-food-fries-nuggets.png",
    {"FOOD", "Beef Nachos"} => "/images/coffeespot/gen-food-beef-nachos.png",
    {"FOOD", "Quesadillas"} => "/images/coffeespot/gen-food-quesadillas.png",
    {"FOOD", "Chicken & Chips"} => "/images/coffeespot/gen-food-chicken-chips.png",
    {"FOOD", "Spam & Chips"} => "/images/coffeespot/gen-food-spam-chips.png",
    {"FOOD", "Slow-Roasted Chicken Sourdough"} =>
      "/images/coffeespot/food-slow-roasted-chicken-sourdough.png",
    {"FOOD", "Golden Egg Royale"} => "/images/coffeespot/food-golden-egg-royale.png",
    {"FOOD", "Tuna Royale Baguette"} => "/images/coffeespot/food-tuna-royale-baguette.png",
    {"FOOD", "BNN Cream Cheese"} => "/images/coffeespot/gen-food-bnn-cream-cheese.png",
    {"FOOD", "BNN Choco Overload"} => "/images/coffeespot/gen-food-bnn-choco-overload.png",
    {"FOOD", "BNN Biscoff"} => "/images/coffeespot/gen-food-bnn-biscoff.png",
    {"FOOD", "Choco Chips"} => "/images/coffeespot/gen-food-choco-chips-muffin.png",
    {"FOOD", "Red Velvet"} => "/images/coffeespot/gen-food-red-velvet.png",
    {"FOOD", "Dark Choco Dream Cake"} => "/images/coffeespot/gen-food-dark-choco-cake.png",
    {"FOOD", "Choco Chip Cookies"} => "/images/coffeespot/gen-food-choco-chip-cookies.png",
    {"FOOD", "BNN Moist Slice"} => "/images/coffeespot/gen-food-bnn-moist-slice.png",
    {"FOOD", "Choco Moist Slice"} => "/images/coffeespot/gen-food-choco-moist-slice.png",
    {"FOOD", "Carrot Moist Slice"} => "/images/coffeespot/gen-food-carrot-moist-slice.png",
    {"FOOD", "Belgian Waffles"} => "/images/coffeespot/gen-food-belgian-waffles.png",
    {"FOOD", "Chocolate Almond Waffles"} => "/images/coffeespot/gen-food-choco-almond-waffles.png"
  }

  @category_images %{
    "HOT" => [
      "/images/coffeespot/gen-hot-espresso.png",
      "/images/coffeespot/gen-hot-cafe-latte.png",
      "/images/coffeespot/gen-hot-americano.png",
      "/images/coffeespot/gen-hot-cappuccino.png"
    ],
    "COLD" => [
      "/images/coffeespot/gen-cold-cafe-latte.png",
      "/images/coffeespot/gen-cold-americano.png",
      "/images/coffeespot/gen-cold-mocha-latte.png",
      "/images/coffeespot/gen-cold-hazelnut.png"
    ],
    "FRAPPE" => [
      "/images/coffeespot/gen-frappe-salted-caramel.png",
      "/images/coffeespot/gen-frappe-mocha.png",
      "/images/coffeespot/gen-frappe-matcha.png",
      "/images/coffeespot/gen-frappe-butter-scotch.png"
    ],
    "SODA" => [
      "/images/coffeespot/gen-soda-tropical-passion.png",
      "/images/coffeespot/gen-soda-hummingbird.png",
      "/images/coffeespot/gen-soda-minty-peach.png"
    ],
    "FOOD" => [
      "/images/coffeespot/gen-food-beef-tapa.png",
      "/images/coffeespot/gen-food-belgian-waffles.png",
      "/images/coffeespot/gen-food-quesadillas.png",
      "/images/coffeespot/gen-food-nugget.png",
      "/images/coffeespot/food-slow-roasted-chicken-sourdough.png"
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
    {"HOT", "Signature Tablea"} => "Rich local cacao, our signature blend",
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
    {"SODA", "Green Apple Campagna"} => "Crisp green apple soda with a refreshing tart finish.",
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

  def sweets_product?(%{menu_group: group}) when group in @sweets_subcategory_names, do: true

  def sweets_product?(%{name: name}), do: sweets_product_name?(name)

  def sweets_product?(_), do: false

  @signature_product_name "Signature Tablea"

  @doc "Canonical name for the CoffeeSpot signature cacao drink."
  def signature_product_name, do: @signature_product_name

  @doc "True when the product is the featured Signature Tablea SKU."
  def signature_product?(name) when is_binary(name), do: name == @signature_product_name
  def signature_product?(_), do: false

  @doc """
  Finds the available Signature Tablea product inside `list_menu/0` categories.

  Returns `{category_name, product}` or `nil`.
  """
  def find_signature_product(categories) when is_list(categories) do
    Enum.find_value(categories, fn category ->
      case Enum.find(category.products, &signature_product?(&1.name)) do
        nil -> nil
        product -> {category.name, product}
      end
    end)
  end

  def find_signature_product(_), do: nil

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

  def category_names, do: @category_order

  def food_group_names, do: Enum.map(@food_subcategories, &elem(&1, 0))

  @doc """
  Creates a catalog product with prices when the actor has `:edit_menu`.

  New items are available immediately on the QR menu and POS.
  """
  def create_product_as(%User{} = actor, attrs) when is_map(attrs) do
    with :ok <- Authorization.authorize(actor, :edit_menu),
         {:ok, category} <- fetch_category(attrs),
         {:ok, name} <- fetch_name(attrs),
         {:ok, menu_group} <- fetch_menu_group(category, attrs),
         {:ok, prices} <- fetch_prices(category, attrs) do
      insert_product_with_prices(category, name, menu_group, prices)
    end
  end

  @doc """
  Attaches a custom photo to a product. QR menu and POS use it immediately.
  """
  def put_product_photo_as(%User{} = actor, product_id, binary, content_type)
      when is_integer(product_id) and is_binary(binary) do
    with :ok <- Authorization.authorize(actor, :edit_menu),
         %Product{} = product <- Repo.get(Product, product_id),
         {:ok, type} <- normalize_photo_type(content_type),
         :ok <- validate_photo_bytes(binary) do
      upsert_product_photo(product, binary, type)
    else
      nil -> {:error, :not_found}
      {:error, :unauthorized} = err -> err
      {:error, reason} -> {:error, reason}
    end
  end

  def get_product_photo(product_id) when is_integer(product_id) do
    case Repo.get(Product, product_id) do
      %Product{has_custom_photo: true} ->
        Repo.get_by(ProductPhoto, product_id: product_id)

      _ ->
        nil
    end
  end

  def photo_max_bytes, do: @photo_max_bytes

  defp normalize_photo_type(type) when type in @photo_types, do: {:ok, type}
  defp normalize_photo_type("image/jpg"), do: {:ok, "image/jpeg"}
  defp normalize_photo_type(_), do: {:error, :invalid_photo}

  defp validate_photo_bytes(binary) do
    size = byte_size(binary)

    cond do
      size < 32 -> {:error, :invalid_photo}
      size > @photo_max_bytes -> {:error, :photo_too_large}
      true -> :ok
    end
  end

  defp upsert_product_photo(product, binary, content_type) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      photo =
        case Repo.get_by(ProductPhoto, product_id: product.id) do
          nil -> %ProductPhoto{product_id: product.id}
          existing -> existing
        end

      {:ok, _photo} =
        photo
        |> ProductPhoto.changeset(%{content_type: content_type, data: binary})
        |> Repo.insert_or_update()

      {:ok, updated} =
        product
        |> Product.changeset(%{has_custom_photo: true, photo_updated_at: now})
        |> Repo.update()

      updated
    end)
    |> case do
      {:ok, product} -> {:ok, product}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_category(attrs) do
    name = attrs |> attr(:category) |> to_string() |> String.trim()

    cond do
      name not in @category_order ->
        {:error, :invalid_category}

      true ->
        case Repo.get_by(Category, name: name) do
          %Category{} = category -> {:ok, category}
          nil -> {:error, :unknown_category}
        end
    end
  end

  defp fetch_name(attrs) do
    name = attrs |> attr(:name) |> to_string() |> String.trim()

    if name == "" or String.length(name) > 80 do
      {:error, :invalid_name}
    else
      {:ok, name}
    end
  end

  defp fetch_menu_group(%{name: "FOOD"}, attrs) do
    group = attrs |> attr(:menu_group) |> to_string() |> String.trim()

    if group in food_group_names() do
      {:ok, group}
    else
      {:error, :invalid_menu_group}
    end
  end

  defp fetch_menu_group(_category, _attrs), do: {:ok, nil}

  defp fetch_prices(%{name: "HOT"}, attrs) do
    case attr(attrs, :hot_price_mode) |> to_string() do
      "single" -> sized_prices([{nil, attr(attrs, :price)}])
      _ -> sized_prices([{"8oz", attr(attrs, :price_8oz)}, {"12oz", attr(attrs, :price_12oz)}])
    end
  end

  defp fetch_prices(%{name: category}, attrs) when category in ["COLD", "FRAPPE", "SODA"] do
    sized_prices([{"16oz", attr(attrs, :price)}])
  end

  defp fetch_prices(%{name: "FOOD"}, attrs) do
    sized_prices([{nil, attr(attrs, :price)}])
  end

  defp fetch_prices(_category, _attrs), do: {:error, :invalid_category}

  defp sized_prices(pairs) do
    parsed =
      Enum.reduce_while(pairs, [], fn {size, raw}, acc ->
        case parse_price(raw) do
          {:ok, price} -> {:cont, acc ++ [{size, price}]}
          :error -> {:halt, :error}
        end
      end)

    case parsed do
      :error -> {:error, :invalid_price}
      prices -> {:ok, prices}
    end
  end

  defp parse_price(value) do
    text = value |> to_string() |> String.trim() |> String.replace(",", "")

    case Decimal.parse(text) do
      {decimal, ""} ->
        if Decimal.compare(decimal, 0) == :gt do
          {:ok, Decimal.round(decimal, 2)}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp insert_product_with_prices(category, name, menu_group, prices) do
    changeset =
      %Product{}
      |> Product.changeset(%{
        name: name,
        category_id: category.id,
        available: true,
        menu_group: menu_group
      })

    Repo.transaction(fn ->
      case Repo.insert(changeset) do
        {:ok, product} ->
          Enum.each(prices, fn {size, price} ->
            {:ok, _} =
              %ProductPrice{}
              |> ProductPrice.changeset(%{
                product_id: product.id,
                size: size,
                price: price
              })
              |> Repo.insert()
          end)

          Repo.preload(product, [:category, :product_prices])

        {:error, %Ecto.Changeset{} = failed} ->
          Repo.rollback(name_error(failed))
      end
    end)
    |> case do
      {:ok, product} -> {:ok, product}
      {:error, reason} -> {:error, reason}
    end
  end

  defp name_error(%Ecto.Changeset{} = changeset) do
    if Keyword.has_key?(changeset.errors, :name) and
         unique_name_error?(changeset.errors[:name]) do
      :name_taken
    else
      :invalid_name
    end
  end

  defp unique_name_error?({_msg, opts}), do: opts[:constraint] == :unique
  defp unique_name_error?(_), do: false

  @doc """
  Absolute public URL for a CoffeeSpot QR menu landing page (`/menu`).

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
    grouped = Enum.group_by(products, &food_group_name/1)
    known = Enum.map(@food_subcategories, &elem(&1, 0))

    extras =
      grouped
      |> Map.keys()
      |> Enum.reject(&(&1 in known or is_nil(&1)))
      |> Enum.sort()

    (known ++ extras)
    |> Enum.map(fn group ->
      %{name: group, products: Map.get(grouped, group, [])}
    end)
    |> Enum.reject(&(&1.products == []))
  end

  defp food_group_name(%{menu_group: group}) when is_binary(group) and group != "", do: group

  defp food_group_name(%{name: name}) do
    Enum.find_value(@food_subcategories, fn {group, names} ->
      if name in names, do: group
    end) || "Other"
  end

  defp category_position(%{name: name}) do
    Enum.find_index(@category_order, &(&1 == name)) || length(@category_order)
  end

  defp price_sort_key(%{size: nil}), do: {0, ""}
  defp price_sort_key(%{size: size}), do: {1, size}

  # Bump when regenerating priv/static/images/coffeespot/pos-thumbs/ so tablets
  # fetch fresh files via Plug.Static ?vsn= long-cache.
  @pos_thumb_vsn "pos1"

  @doc """
  Public image path for a menu item. Custom tablet photo first, then named
  CoffeeSpot photos, then a stable category fallback so every card has a photo.
  """
  def product_image(category_name, %{name: name} = product)
      when is_binary(category_name) and is_binary(name) do
    custom_photo_url(product) || product_image(category_name, name)
  end

  def product_image(category_name, product_name)
      when is_binary(category_name) and is_binary(product_name) do
    Map.get(@product_images, {category_name, product_name}) ||
      category_fallback_image(category_name, product_name)
  end

  @doc "Image path plus whether it should render as a packshot (contain)."
  def product_image_meta(category_name, product)
      when is_binary(category_name) and (is_map(product) or is_binary(product)) do
    src = product_image(category_name, product)
    %{src: src, packshot?: packshot_image?(src)}
  end

  @doc """
  POS tablet image meta: lightweight WebP thumb under `/images/coffeespot/pos-thumbs/`
  with `?vsn=` for long-lived HTTP cache. Falls back to the full image if missing.

  Custom photos skip thumbs and use `/media/products/:id`.
  Customer menu and API must keep using `product_image/2` / `product_image_meta/2`.
  """
  def pos_product_image_meta(category_name, %{name: name} = product)
      when is_binary(category_name) and is_binary(name) do
    case custom_photo_url(product) do
      nil -> pos_product_image_meta(category_name, name)
      url -> %{src: url, packshot?: false}
    end
  end

  def pos_product_image_meta(category_name, product_name)
      when is_binary(category_name) and is_binary(product_name) do
    full = product_image(category_name, product_name)
    packshot? = packshot_image?(full)

    case pos_thumb_url(full) do
      {:ok, thumb_url} ->
        %{src: thumb_url, packshot?: packshot?}

      :missing ->
        %{src: full, packshot?: packshot?}
    end
  end

  defp custom_photo_url(%{id: id, has_custom_photo: true} = product) when is_integer(id) do
    "/media/products/#{id}?v=#{photo_cache_v(Map.get(product, :photo_updated_at), id)}"
  end

  defp custom_photo_url(_), do: nil

  defp photo_cache_v(%DateTime{} = at, _id), do: DateTime.to_unix(at)
  defp photo_cache_v(_, id), do: id

  @doc "True when the image is a transparent packshot PNG (prefer contain in UI)."
  def packshot_image?(path) when is_binary(path) do
    path
    |> String.split("?", parts: 2)
    |> hd()
    |> String.downcase()
    |> String.ends_with?(".png")
  end

  def packshot_image?(_), do: false

  defp pos_thumb_url("/images/coffeespot/" <> name) do
    stem = Path.rootname(name)
    relative = "images/coffeespot/pos-thumbs/#{stem}.webp"
    absolute = Application.app_dir(:espreso, Path.join("priv/static", relative))

    if File.exists?(absolute) do
      {:ok, "/#{relative}?vsn=#{@pos_thumb_vsn}"}
    else
      :missing
    end
  end

  defp pos_thumb_url(_other), do: :missing

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
