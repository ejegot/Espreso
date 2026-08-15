defmodule Espreso.Menu do
  @moduledoc """
  The Menu context for loading customer-facing menu data.
  """

  import Ecto.Query

  alias Espreso.Repo
  alias Espreso.Menu.{Category, Product}

  @category_order ~w(HOT COLD FRAPPE SODA FOOD)

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
  Updates whether a product is available on the customer menu.

  Returns `{:ok, product}` or `{:error, changeset}`.
  """
  def update_product_availability(%Product{} = product, available) do
    product
    |> Product.changeset(%{available: available})
    |> Repo.update()
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
